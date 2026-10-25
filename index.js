// 余音 B站接口：直接调用 B站公开接口搜索视频，并转发音频流（浏览器无法自带 Referer，所以由服务端转发）。
// 不需要登录。故意不带 buvid 等 cookie：未激活的 buvid 反而会触发搜索风控（返回 v_voucher 和空结果）。
import crypto from 'node:crypto';
import { Readable } from 'node:stream';

export const info = {
    id: 'yuyin-bili',
    name: '余音 B站接口',
    description: 'Bilibili search and audio relay for the 余音 music player script.',
};

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36';
const API_HEADERS = { 'User-Agent': UA, Referer: 'https://www.bilibili.com/' };
// The audio CDN rejects some nodes when a User-Agent is sent; Referer alone works on every node we tested.
const MEDIA_HEADERS = { Referer: 'https://www.bilibili.com/' };
const MIXIN = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52];
const BV = /^BV[0-9A-Za-z]{10}$/;
const MEDIA_HOST = /(^|\.)(bilivideo\.com|bilivideo\.cn|akamaized\.net|hdslb\.com)$/;

let wbi = { key: '', expires: 0 };
const streams = new Map();

async function api(url, signal) {
    let response;
    for (let attempt = 0; ; attempt++) {
        try { response = await fetch(url, { headers: API_HEADERS, signal }); break; }
        catch (error) { if (signal?.aborted || attempt >= 2) throw Object.assign(new Error('连接 B站失败，请稍后再试'), { status: 502 }); await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1))); }
    }
    const text = await response.text();
    let body;
    try { body = JSON.parse(text); } catch { throw Object.assign(new Error(`B站接口异常（HTTP ${response.status}）`), { status: 502 }); }
    return body;
}

async function mixinKey(force = false) {
    if (!force && wbi.key && wbi.expires > Date.now()) return wbi.key;
    const nav = await api('https://api.bilibili.com/x/web-interface/nav');
    const name = url => String(url || '').split('/').pop().split('.')[0];
    const raw = name(nav.data?.wbi_img?.img_url) + name(nav.data?.wbi_img?.sub_url);
    if (raw.length < 64) throw Object.assign(new Error('B站签名密钥获取失败'), { status: 502 });
    wbi = { key: MIXIN.map(i => raw[i]).join('').slice(0, 32), expires: Date.now() + 3600_000 };
    return wbi.key;
}

async function signed(base, params, signal) {
    for (let attempt = 0; attempt < 2; attempt++) {
        const key = await mixinKey(attempt > 0);
        const all = { ...params, wts: Math.floor(Date.now() / 1000) };
        const query = Object.keys(all).sort().map(k => `${encodeURIComponent(k)}=${encodeURIComponent(String(all[k]).replace(/[!'()*]/g, ''))}`).join('&');
        const body = await api(`${base}?${query}&w_rid=${crypto.createHash('md5').update(query + key).digest('hex')}`, signal);
        if (body.code !== -403 && body.code !== -352) return body;
    }
    throw Object.assign(new Error('B站拒绝了签名请求，请稍后再试'), { status: 503 });
}

const text = value => String(value || '').replace(/<[^>]+>/g, '').replace(/&(amp|lt|gt|quot|#39);/g, (_, e) => ({ amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" })[e]).trim();
const seconds = value => String(value || '').split(':').reduce((sum, part) => sum * 60 + (Number(part) || 0), 0);

async function search(keyword, page, signal) {
    let last;
    for (let attempt = 0; attempt < 3; attempt++) {
        if (attempt) await new Promise(resolve => setTimeout(resolve, 800 * attempt));
        last = await signed('https://api.bilibili.com/x/web-interface/wbi/search/type', { search_type: 'video', keyword, page }, signal);
        if (last.code !== 0) throw Object.assign(new Error(`B站搜索失败（${last.code}）：${last.message || ''}`), { status: 502 });
        const rows = last.data?.result || [];
        // An empty list with v_voucher is risk control, not "no results"; retry before giving up.
        if (rows.length || !last.data?.v_voucher) {
            return rows.filter(row => BV.test(row.bvid)).map(row => ({
                id: row.bvid,
                name: text(row.title) || row.bvid,
                artist: [text(row.author) || 'B站'],
                album: '',
                source: 'bilibili',
                pic_id: row.pic ? (row.pic.startsWith('//') ? 'https:' + row.pic : row.pic) : '',
                lyric_id: row.bvid,
                extra_data: { duration: seconds(row.duration) },
            }));
        }
    }
    throw Object.assign(new Error('B站搜索暂时被风控，过十几秒再试'), { status: 503 });
}

async function audioUrls(bvid, page, signal) {
    const cacheKey = `${bvid}:${page}`;
    const cached = streams.get(cacheKey);
    if (cached && cached.expires > Date.now()) return cached.urls;
    const pages = await api(`https://api.bilibili.com/x/player/pagelist?bvid=${bvid}`, signal);
    const part = (pages.data || [])[page - 1];
    if (pages.code !== 0 || !part?.cid) throw Object.assign(new Error('这个B站视频不存在或已失效'), { status: 404 });
    const play = await signed('https://api.bilibili.com/x/player/wbi/playurl', { bvid, cid: part.cid, fnval: 16, fourk: 0 }, signal);
    const dash = play.data?.dash;
    const tracks = [...(dash?.audio || []), ...(dash?.flac?.audio ? [dash.flac.audio] : [])].sort((a, b) => (b.bandwidth || 0) - (a.bandwidth || 0));
    const urls = tracks.flatMap(track => [track.baseUrl || track.base_url, ...(track.backupUrl || track.backup_url || [])])
        .filter(url => { try { const u = new URL(url); return u.protocol === 'https:' && MEDIA_HOST.test(u.hostname); } catch { return false; } });
    if (play.code !== 0 || !urls.length) throw Object.assign(new Error('这个B站视频没有可播放的音频（可能需要登录或大会员）'), { status: 404 });
    streams.set(cacheKey, { urls, expires: Date.now() + 20 * 60_000 });
    if (streams.size > 200) streams.delete(streams.keys().next().value);
    return urls;
}

async function relay(req, res, bvid, page) {
    const controller = new AbortController();
    res.on('close', () => controller.abort());
    const headers = { ...MEDIA_HEADERS, ...(req.headers.range ? { Range: req.headers.range } : {}) };
    for (let round = 0; round < 2; round++) {
        if (round) streams.delete(`${bvid}:${page}`);
        for (const url of await audioUrls(bvid, page, controller.signal)) {
            let upstream;
            try { upstream = await fetch(url, { headers, signal: controller.signal }); } catch (error) { if (controller.signal.aborted) return; continue; }
            if (upstream.status !== 200 && upstream.status !== 206) { await upstream.body?.cancel(); continue; }
            res.status(upstream.status);
            res.setHeader('Content-Type', 'audio/mp4');
            res.setHeader('Accept-Ranges', 'bytes');
            res.setHeader('Cache-Control', 'no-store');
            for (const name of ['content-length', 'content-range']) { const value = upstream.headers.get(name); if (value) res.setHeader(name, value); }
            Readable.fromWeb(upstream.body).on('error', () => res.destroy()).pipe(res);
            return;
        }
    }
    throw Object.assign(new Error('B站音频节点都拒绝了请求，请稍后再试'), { status: 502 });
}

function fail(res, error) {
    if (res.headersSent) { res.destroy(); return; }
    if (error?.name === 'AbortError') return;
    res.status(error?.status || 500).json({ error: error?.message || 'B站接口出错' });
}

export async function init(router) {
    router.get('/health', (_req, res) => res.json({ ok: true, version: '1.0.1' }));
    router.get('/search', async (req, res) => {
        const keyword = String(req.query.keyword || '').trim().slice(0, 100);
        const page = Math.max(1, Math.min(10, Number(req.query.page) || 1));
        if (!keyword) return res.status(400).json({ error: '请输入搜索关键词' });
        try { res.json(await search(keyword, page)); } catch (error) { fail(res, error); }
    });
    router.get('/stream/:bvid', async (req, res) => {
        const bvid = String(req.params.bvid);
        const page = Math.max(1, Math.min(999, Number(req.query.p) || 1));
        if (!BV.test(bvid)) return res.status(400).json({ error: 'B站视频编号无效' });
        try { await relay(req, res, bvid, page); } catch (error) { fail(res, error); }
    });
}

export async function exit() {
    streams.clear();
}
