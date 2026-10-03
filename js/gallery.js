// Photography page: drone films, category tabs, gallery and full-screen viewer.
// The gallery is built from Pictures/Photography/photos.json, a list like:
// [
//   { "file": "web/full/x.jpg", "thumb": "web/thumbs/x.jpg", "width": 1333, "height": 2000,
//     "title": "Lion", "category": "Animals", "meta": "Sony a7 III · 2026", "alt": "Male lion lying in the dirt" }
// ]
// Only "file" is required. Paths are relative to Pictures/Photography/.

(function () {
    var DIR = 'Pictures/Photography/';

    var $ = function (id) { return document.getElementById(id); };

    var photos = [];
    var visible = [];
    var current = 0;

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text) node.textContent = text;
        return node;
    }

    // ---- Drone films ----
    // Always autoplay (muted, looping). They pause while scrolled off screen,
    // and one button lets visitors pause both.

    var videos = Array.prototype.slice.call(document.querySelectorAll('.ph-film video'));
    var toggle = $('film-toggle');
    var paused = false;

    function tryPlay(v) {
        if (paused || v.dataset.onscreen === '0') return;
        v.muted = true; // some browsers only allow autoplay when muted is set as a property
        var p = v.play();
        if (p && p.catch) p.catch(function () {});
    }

    function setPaused(p) {
        paused = p;
        toggle.setAttribute('aria-pressed', p ? 'true' : 'false');
        toggle.querySelector('i').className = p ? 'bi bi-play-fill' : 'bi bi-pause-fill';
        toggle.querySelector('span').textContent = p ? 'Play films' : 'Pause films';
        videos.forEach(function (v) { if (p) v.pause(); else tryPlay(v); });
    }

    videos.forEach(function (v) {
        // Start as soon as enough data has arrived.
        v.addEventListener('canplay', function () { tryPlay(v); });
        tryPlay(v);
    });

    if ('IntersectionObserver' in window) {
        var io = new IntersectionObserver(function (entries) {
            entries.forEach(function (e) {
                e.target.dataset.onscreen = e.isIntersecting ? '1' : '0';
                if (e.isIntersecting) tryPlay(e.target);
                else e.target.pause();
            });
        }, { threshold: 0.1 });
        videos.forEach(function (v) { io.observe(v); });
    }

    // Low Power Mode on iPhone/Mac blocks autoplay; start on the first tap, scroll or key press instead.
    function kick() {
        videos.forEach(function (v) { if (v.paused) tryPlay(v); });
        ['pointerdown', 'touchstart', 'scroll', 'keydown'].forEach(function (t) {
            window.removeEventListener(t, kick);
        });
    }
    ['pointerdown', 'touchstart', 'scroll', 'keydown'].forEach(function (t) {
        window.addEventListener(t, kick, { passive: true });
    });

    toggle.addEventListener('click', function () { setPaused(!paused); });

    // ---- Gallery ----

    function render(list) {
        photos = (Array.isArray(list) ? list : []).filter(function (p) { return p && p.file; });
        if (!photos.length) {
            $('empty').hidden = false;
            return;
        }
        buildGallery();
        buildTabs();
        applyFilter('All');
    }

    function buildGallery() {
        var gallery = $('gallery');
        photos.forEach(function (p, i) {
            var fig = el('figure', 'photo');

            var btn = el('button');
            btn.type = 'button';
            btn.setAttribute('aria-label', 'View ' + (p.title || 'photo ' + (i + 1)));
            btn.addEventListener('click', function () { openViewer(p); });

            var img = el('img');
            img.src = DIR + (p.thumb || p.file);
            img.alt = p.alt || p.title || '';
            if (p.width && p.height) { img.width = p.width; img.height = p.height; }
            img.loading = 'lazy';
            img.decoding = 'async';
            btn.appendChild(img);
            fig.appendChild(btn);

            if (p.title || p.meta) {
                var cap = el('figcaption');
                cap.appendChild(el('span', 'photo-title', p.title || ''));
                if (p.meta) cap.appendChild(el('span', 'meta', p.meta));
                fig.appendChild(cap);
            }

            p.node = fig;
            gallery.appendChild(fig);
        });
    }

    function buildTabs() {
        var counts = {};
        var cats = [];
        photos.forEach(function (p) {
            if (!p.category) return;
            if (!counts[p.category]) { counts[p.category] = 0; cats.push(p.category); }
            counts[p.category]++;
        });
        if (cats.length < 2) return;
        counts.All = photos.length;

        var tabs = $('filters');
        ['All'].concat(cats).forEach(function (cat) {
            var b = el('button', 'ph-tab', cat);
            b.type = 'button';
            b.dataset.cat = cat;
            b.appendChild(el('span', 'n', String(counts[cat])));
            b.addEventListener('click', function () { applyFilter(cat); });
            tabs.appendChild(b);
        });
        tabs.hidden = false;
    }

    function applyFilter(cat) {
        visible = photos.filter(function (p) {
            var show = cat === 'All' || p.category === cat;
            p.node.hidden = !show;
            return show;
        });
        Array.prototype.forEach.call($('filters').children, function (b) {
            b.setAttribute('aria-pressed', b.dataset.cat === cat ? 'true' : 'false');
        });
    }

    // ---- Lightbox ----

    var lightbox = $('lightbox');

    function show(i) {
        current = (i + visible.length) % visible.length;
        var p = visible[current];
        $('lb-img').src = DIR + p.file;
        $('lb-img').alt = p.alt || p.title || '';
        $('lb-title').textContent = p.title || '';
        $('lb-meta').textContent = p.meta || '';
        $('lb-count').textContent = (current + 1) + ' / ' + visible.length;
        var single = visible.length < 2;
        $('lb-prev').hidden = single;
        $('lb-next').hidden = single;
        // Warm the cache for the next photo.
        if (!single) new Image().src = DIR + visible[(current + 1) % visible.length].file;
    }

    function openViewer(p) {
        show(visible.indexOf(p));
        lightbox.showModal();
    }

    $('lb-close').addEventListener('click', function () { lightbox.close(); });
    $('lb-prev').addEventListener('click', function () { show(current - 1); });
    $('lb-next').addEventListener('click', function () { show(current + 1); });

    // Click on the empty area around the photo closes the viewer.
    $('lb-stage').addEventListener('click', function (e) {
        if (e.target === e.currentTarget) lightbox.close();
    });

    lightbox.addEventListener('keydown', function (e) {
        if (e.key === 'ArrowLeft') show(current - 1);
        if (e.key === 'ArrowRight') show(current + 1);
    });

    // Swipe left/right on touch screens.
    var startX = null;
    lightbox.addEventListener('touchstart', function (e) { startX = e.touches[0].clientX; }, { passive: true });
    lightbox.addEventListener('touchend', function (e) {
        if (startX === null) return;
        var dx = e.changedTouches[0].clientX - startX;
        if (Math.abs(dx) > 50) show(current + (dx < 0 ? 1 : -1));
        startX = null;
    });

    lightbox.addEventListener('close', function () { $('lb-img').removeAttribute('src'); });

    fetch(DIR + 'photos.json')
        .then(function (r) { return r.ok ? r.json() : []; })
        .catch(function () { return []; })
        .then(render);
})();
