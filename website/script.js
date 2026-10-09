(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const sleep = (ms) => new Promise((r) => setTimeout(r, reduce ? 0 : ms));
  const escapeHTML = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  const COLOR = { orange: "#ff7a45", blue: "#6ea8ff", pink: "#ff5c93", green: "#3fae7a", yellow: "#ffd23f" };

  // Run fn once, the first time el is on screen.
  function onVisible(el, fn, threshold = 0.35) {
    if (!el) return;
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        io.disconnect();
        fn();
      }
    }, { threshold });
    io.observe(el);
  }

  /* The work: small client designs, drawn in CSS so they stay crisp at any size */
  const ART = {
    menu: (v) => `
      <span class="m-brand">Larkspur Coffee</span>
      <b class="m-title">Holiday Menu</b>
      <ul>
        <li><span>Gingerbread latte${v === "new" ? '<i class="m-new">NEW</i>' : ""}</span><em>5.50</em></li>
        <li><span>Maple oat cortado</span><em>5.00</em></li>
        <li><span>Cranberry scone</span><em>3.75</em></li>
        <li><span>Oat milk</span><em>+0.75</em></li>
      </ul>
      <span class="m-foot">Open 7 to 3, every day</span>`,
    label: () => '<span class="l-mark">L</span><b class="l-name">Winter<br>Blend</b><span class="l-sub">Whole bean, 12 oz</span>',
    post: (v) => `<span class="p-brand">Larkspur Coffee</span><b class="p-big">${v === "alt" ? "Maple cortado season." : "Gingerbread is back."}</b>`,
    web: (v) => `
      <div class="w-nav"><i></i>TIDEWATER ARCHERY<span>Lessons &nbsp; Events &nbsp; Coaches</span></div>
      <div class="w-body">
        <div>
          <h5>Coach with us this spring.</h5>
          <p class="w-lede">Teach beginners on Saturday mornings. We cover your certification.</p>
          <div class="w-form"><span>Name</span><span>Email</span><span>Certification level</span><b class="w-btn">${v === "apply" ? "Apply to coach" : "Send application"}</b></div>
        </div>
        <div class="w-target"></div>
      </div>`,
    poster: () => `
      <span class="x-label">MOTH RECORDS</span>
      <b class="x-big">SPRING<br>TOUR</b>
      <ul><li><span>MAR 12</span><b>Portland</b></li><li><span>MAR 14</span><b>Seattle</b></li><li><span>MAR 17</span><b>Boise</b></li><li><span>MAR 20</span><b>Denver</b></li></ul>`,
    page: (v) => {
      const title = { 1: "Tournament Handbook", 2: "Scoring", 3: "Equipment" }[v] || "Tournament Handbook";
      const foot = v || "1";
      const table = v === "2" ? '<div class="g-table">' + "<i></i>".repeat(12) + "</div>" : "";
      const widths = [96, 88, 92, 70, 94, 84, 60];
      return `<span class="g-head">Tidewater Archery</span><h6>${title}</h6>
        <div class="g-lines">${widths.map((w) => `<i style="width:${w}%"></i>`).join("")}</div>${table}
        <div class="g-lines">${widths.slice(2).map((w) => `<i style="width:${w}%"></i>`).join("")}</div>
        <span class="g-foot">${foot}</span>`;
    },
  };

  function drawArt(el) {
    const type = el.dataset.art;
    if (!ART[type]) return;
    el.classList.add(`art--${type}`);
    el.innerHTML = `<div class="art__in">${ART[type](el.dataset.variant)}</div>`;
  }
  $$("[data-art]").forEach(drawArt);

  /* Scroll reveals */
  const revealer = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add("in");
      revealer.unobserve(e.target);
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
  $$(".reveal").forEach((el) => revealer.observe(el));

  /* GitHub stars, honestly reported */
  fetch("https://api.github.com/repos/shelbyklein/chatterbox")
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || typeof data.stargazers_count !== "number") return;
      const n = data.stargazers_count;
      $("[data-stars]").textContent = n > 0 ? `${n.toLocaleString()} star${n === 1 ? "" : "s"}` : "Be star #1";
    })
    .catch(() => {});

  /* Confetti */
  const canvas = $("#confetti");
  const ctx = canvas.getContext("2d");
  const PALETTE = Object.values(COLOR).concat("#f4f0ea");
  let bits = [];
  let raf = 0;
  let dpr = 1;

  function sizeCanvas() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = innerWidth * dpr;
    canvas.height = innerHeight * dpr;
  }
  sizeCanvas();
  addEventListener("resize", sizeCanvas);

  function burst(x, y, count = 90, palette = PALETTE) {
    if (reduce) return;
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 4 + Math.random() * 9;
      bits.push({
        x, y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 6,
        w: 5 + Math.random() * 6,
        h: 3 + Math.random() * 5,
        rot: Math.random() * Math.PI,
        spin: (Math.random() - 0.5) * 0.35,
        color: palette[i % palette.length],
        round: Math.random() < 0.3,
        life: 0,
      });
    }
    if (!raf) raf = requestAnimationFrame(tick);
  }

  function tick() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    bits = bits.filter((b) => b.life < 200 && b.y < innerHeight + 40);
    for (const b of bits) {
      b.vx *= 0.985;
      b.vy = b.vy * 0.985 + 0.32;
      b.x += b.vx;
      b.y += b.vy;
      b.rot += b.spin;
      b.life++;
      ctx.save();
      ctx.globalAlpha = Math.min(1, (200 - b.life) / 40);
      ctx.translate(b.x, b.y);
      ctx.rotate(b.rot);
      ctx.fillStyle = b.color;
      if (b.round) {
        ctx.beginPath();
        ctx.arc(0, 0, b.h * 0.7, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.fillRect(-b.w / 2, -b.h / 2, b.w, b.h);
      }
      ctx.restore();
    }
    raf = bits.length ? requestAnimationFrame(tick) : 0;
    if (!raf) ctx.clearRect(0, 0, innerWidth, innerHeight);
  }

  function burstFrom(el, count, palette) {
    const r = el.getBoundingClientRect();
    burst(r.left + r.width / 2, r.top + r.height / 2, count, palette);
  }

  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-confetti]");
    if (t) burstFrom(t);
  });

  /* Hero: ask for a change, watch it land in the chat */
  const hero = $("[data-hero]");
  if (hero) {
    const field = $(".ax-field", hero);
    const typed = $("[data-hero-type]", hero);
    const send = $("[data-hero-send]", hero);
    const spin = $("[data-hero-spin]", hero);
    const stepsLabel = $("[data-hero-steps]", hero);
    const stream = $("[data-hero-stream]", hero);
    const step = (n) => $(`[data-hero-step="${n}"]`, hero);
    const reply = stream.textContent;
    const ask = step(1).textContent;

    function newImage() {
      const fig = document.createElement("div");
      fig.className = "ax-imgs ax-imgs--one";
      fig.innerHTML = '<figure class="ax-img"><div class="ax-img__frame"><div class="art" data-art="menu" data-ratio="1x1" data-variant="new"></div></div><figcaption>holiday-menu-square-v2 <span><i class="ph ph-copy"></i> Copy image</span></figcaption></figure>';
      drawArt($("[data-art]", fig));
      return fig;
    }

    if (reduce) {
      [1, 2, 3].forEach((n) => (step(n).hidden = false));
      step(3).after(newImage());
    } else {
      onVisible(hero, async () => {
        await sleep(1600);
        field.classList.add("typing");
        for (const ch of ask) {
          typed.textContent += ch;
          await sleep(28 + Math.random() * 38);
        }
        await sleep(350);
        send.classList.add("hot");
        await sleep(200);
        typed.textContent = "";
        field.classList.remove("typing");
        send.classList.remove("hot");
        step(1).hidden = false;
        spin.hidden = false;
        await sleep(500);
        step(2).hidden = false;
        stepsLabel.insertAdjacentHTML("afterend", '<span class="spin"></span>');
        await sleep(1700);
        $(".spin", step(2))?.remove();
        stream.textContent = "";
        step(3).hidden = false;
        for (const word of reply.split(" ")) {
          stream.textContent += (stream.textContent ? " " : "") + word;
          await sleep(45 + Math.random() * 40);
        }
        step(3).after(newImage());
        spin.hidden = true;
      }, 0.3);
    }
  }

  /* Chat vs terminal: drag the line */
  const compare = $("[data-compare]");
  if (compare) {
    const range = $("[data-compare-range]", compare);
    const setPos = (v) => compare.style.setProperty("--pos", `${22 + (Number(v) / 100) * 56}%`);
    range.addEventListener("input", () => setPos(range.value));
    range.addEventListener("pointerdown", () => compare.classList.add("dragging"));
    addEventListener("pointerup", () => compare.classList.remove("dragging"));
    setPos(range.value);

    // A small nudge, once, so it's obvious the line moves.
    if (!reduce) {
      onVisible(compare, () => {
        const start = performance.now();
        const frame = (t) => {
          const k = Math.min(1, (t - start) / 1400);
          const v = 50 - Math.sin(k * Math.PI) * 14;
          if (compare.classList.contains("dragging")) return;
          range.value = v;
          setPos(v);
          if (k < 1) requestAnimationFrame(frame);
        };
        setTimeout(() => requestAnimationFrame(frame), 500);
      }, 0.5);
    }
  }

  /* Make, open, collect, review: the window follows the step you're reading */
  const story = $("[data-story]");
  if (story) {
    const win = $(".story__win", story);
    const title = $("[data-story-title]", story);
    const where = $(".ax-bar .ax-menu", win);
    const chooser = $("[data-chooser]", story);
    const CONTEXT = {
      create: ["Coach signup page", "Tidewater Archery"],
      preview: ["Coach signup page", "Tidewater Archery"],
      library: ["Holiday menu boards", "Larkspur Coffee"],
      review: ["Home", "All Studios"],
    };
    let chooserRun = 0;

    async function playChooser() {
      const me = ++chooserRun;
      const opt = $(".chooser__opt.is-hit", chooser);
      chooser.classList.remove("gone");
      opt.classList.remove("pressed");
      if (reduce) { chooser.classList.add("gone"); return; }
      await sleep(1700);
      if (me !== chooserRun) return;
      opt.classList.add("pressed");
      await sleep(500);
      if (me !== chooserRun) return;
      chooser.classList.add("gone");
    }

    function activate(stage) {
      if (win.dataset.active === stage) return;
      win.dataset.active = stage;
      $$(".stage", story).forEach((s) => s.classList.toggle("is-active", s.dataset.stage === stage));
      const [t, w] = CONTEXT[stage];
      title.textContent = t;
      where.innerHTML = `<i class="ph-fill ph-palette"></i> ${escapeHTML(w)} <i class="ph ph-caret-down"></i>`;
      where.hidden = stage === "review";
      if (stage === "preview") playChooser();
    }

    const stageWatcher = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) activate(e.target.dataset.stage);
    }, { rootMargin: "-45% 0px -45% 0px" });
    $$(".stage", story).forEach((s) => stageWatcher.observe(s));
    $(".stage", story).classList.add("is-active");
    chooser.classList.add("gone");

    // On narrow screens each step carries its own copy of the window.
    for (const slot of $$("[data-slot]", story)) {
      const name = slot.dataset.slot;
      const copy = document.createElement("div");
      copy.className = "ax-win";
      copy.setAttribute("aria-hidden", "true");
      const bar = $(".ax-bar", win).cloneNode(true);
      $("[data-story-title]", bar).textContent = CONTEXT[name][0];
      $(".ax-menu", bar).innerHTML = `<i class="ph-fill ph-palette"></i> ${escapeHTML(CONTEXT[name][1])} <i class="ph ph-caret-down"></i>`;
      $("[data-story-title]", bar).removeAttribute("data-story-title");
      copy.append(bar, $(`[data-screen="${name}"]`, win).cloneNode(true));
      slot.append(copy);
    }
  }

  /* Agents: a preset pill switches agent, model and effort in one click */
  const handoff = $("[data-handoff]");
  if (handoff) {
    const log = $("[data-handoff-log]", handoff);
    const placeholder = $("[data-handoff-ph]", handoff);
    const model = $("[data-handoff-model]", handoff);
    const pills = $$("[data-switch]", handoff);
    const AGENTS = {
      codex: {
        name: "Codex",
        model: "Codex · GPT-6.1-Sol · Medium effort",
        divider: "Switched to Codex. It read the whole chat first.",
        reply: "Caught up. I’ll split the table and export it again.",
        colors: [COLOR.green, "#f4f0ea", COLOR.yellow],
      },
      claude: {
        name: "Claude",
        model: "Claude · Opus 5.5 · High effort",
        divider: "Back to Claude. Nothing was lost.",
        reply: "The export worked. The handbook is in the Studio folder.",
        colors: [COLOR.orange, COLOR.yellow, COLOR.pink],
      },
    };
    let busy = false;

    function add(node) {
      log.append(node);
      while (log.children.length > 7) log.firstElementChild.remove();
    }

    pills.forEach((pill) => pill.addEventListener("click", async () => {
      const to = pill.dataset.switch;
      if (busy || handoff.dataset.agent === to) return;
      busy = true;
      const a = AGENTS[to];
      handoff.dataset.agent = to;
      pills.forEach((p) => p.classList.toggle("is-on", p === pill));
      placeholder.textContent = `Message ${a.name}`;
      model.textContent = a.model;
      burstFrom(pill, 32, a.colors);

      const divider = document.createElement("div");
      divider.className = "handoff__divider";
      divider.textContent = a.divider;
      add(divider);

      await sleep(650);
      const msg = document.createElement("p");
      msg.className = "ax-text ax-text--agent enter";
      msg.innerHTML = `<span class="mark mark--${to === "codex" ? "openai" : "claude"}"></span><span></span>`;
      msg.lastElementChild.textContent = a.reply;
      add(msg);
      busy = false;
    }));
  }

  /* Studios & Projects */
  const explorer = $("[data-explorer]");
  if (explorer) {
    const WORKSPACES = {
      larkspur: {
        kind: "studio", name: "Larkspur Coffee",
        instructions: "A small-batch roaster with two cafés. Menus print at 24 × 36 in, and prices live in the shared sheet. Keep the tone warm and a little nerdy.",
      },
      tidewater: {
        kind: "studio", name: "Tidewater Archery",
        instructions: "A youth and adult archery club. The handbook follows the national rulebook. Coaches get every change by email, so flag anything that touches scoring.",
      },
      moth: {
        kind: "studio", name: "Moth Records",
        instructions: "An indie label with six artists and one very busy inbox. Release dates live in the calendar. Never announce a date before the artist does.",
      },
      site: {
        kind: "project", name: "larkspur-site", repo: "you/larkspur-site", branch: "main", ahead: "2",
        note: "Keep the current logo until the rebrand ships.", noteDate: "Oct 6",
      },
      planner: {
        kind: "project", name: "garden-planner", repo: "you/garden-planner", branch: "frost-dates", ahead: "1",
        note: "Zone data comes from the USDA file, not the old CSV.", noteDate: "Oct 4",
      },
    };

    const panel = $("[data-panel]", explorer);
    const tabs = $$("[data-key]", explorer);
    const where = $("[data-where]", explorer);

    function render(key) {
      const w = WORKSPACES[key];
      const studio = w.kind === "studio";
      $("[data-name]", explorer).textContent = w.name;
      $$("[data-kind-icon]", explorer).forEach((i) => i.classList.toggle("is-on", i.dataset.kindIcon === w.kind));
      where.innerHTML = studio
        ? `<i class="ph-fill ph-palette"></i> ${escapeHTML(w.name)} <i class="ph ph-caret-down"></i>`
        : `<i class="ph ph-git-branch"></i> ${escapeHTML(w.repo)} · ${escapeHTML(w.branch)} ↑${w.ahead} <i class="ph ph-caret-down"></i>`;

      $("[data-brief]", panel).innerHTML = studio
        ? `<div class="sheet">
            <h4>${escapeHTML(w.name)} Instructions</h4>
            <p>Every chat in this Studio follows these. Say what it’s for, and point to the sites, files, and tools to use.</p>
            <div class="sheet__box">${escapeHTML(w.instructions)}</div>
            <div class="sheet__file"><b><i class="ph ph-file-text"></i> design.md</b> Every chat reads this before visual work.</div>
          </div>`
        : `<div class="notes">
            <div class="notes__head"><i class="ph ph-note"></i> Project notes <i class="ph ph-caret-up"></i></div>
            <div class="notes__item">${escapeHTML(w.note)}<small>${escapeHTML(w.noteDate)}</small></div>
          </div>`;

      const prompts = studio
        ? [`Tour ${w.name} and its instructions`, `Find unfinished work in ${w.name}`, `Plan the next ${w.name} job`]
        : [`Tour ${w.name} and its current work`, `Find unfinished work in ${w.name}`, `Plan the next ${w.name} improvement`];
      $("[data-prompts]", panel).innerHTML = prompts
        .map((p) => `<button type="button" class="starter"><i class="ph ph-chat-circle-text"></i>${escapeHTML(p)}</button>`)
        .join("");

      panel.classList.remove("swap");
      void panel.offsetWidth;
      panel.classList.add("swap");
    }

    function select(tab) {
      tabs.forEach((t) => {
        const on = t === tab;
        t.classList.toggle("is-on", on);
        t.setAttribute("aria-selected", String(on));
      });
      render(tab.dataset.key);
    }

    tabs.forEach((t) => t.addEventListener("click", () => select(t)));
    explorer.addEventListener("keydown", (e) => {
      if (!["ArrowDown", "ArrowUp", "ArrowRight", "ArrowLeft"].includes(e.key) || !e.target.matches("[data-key]")) return;
      e.preventDefault();
      const i = tabs.indexOf(e.target);
      const next = tabs[(i + (e.key === "ArrowDown" || e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length];
      next.focus();
      select(next);
    });
    panel.addEventListener("click", (e) => {
      const s = e.target.closest(".starter");
      if (s) burstFrom(s, 24, [COLOR.orange, COLOR.yellow, "#f4f0ea"]);
    });

    render("larkspur");
    panel.classList.remove("swap");
  }

  /* Phone: a notification, then the PDF it points to */
  const phone = $("[data-phone]");
  if (phone) {
    const pages = $("[data-pdf-pages]", phone);
    const count = $("[data-pdf-count]", phone);
    const track = document.createElement("div");
    track.className = "pdf__track";
    track.append(...pages.children);
    pages.append(track);

    const open = async () => {
      phone.classList.add("notified");
      await sleep(1500);
      phone.classList.add("tapped");
      await sleep(250);
      phone.classList.add("opened");
      const pageH = track.firstElementChild.getBoundingClientRect().height + 6;
      for (const [i, label] of [[1, "2 of 24"], [2, "3 of 24"]]) {
        await sleep(1800);
        track.style.transform = `translateY(${-pageH * i}px)`;
        count.textContent = label;
      }
    };
    onVisible(phone, () => setTimeout(open, reduce ? 0 : 400), 0.45);
  }

  /* Make it yours: the tone menu and preset names */
  const tuner = $("[data-tuner]");
  if (tuner) {
    const TONES = {
      friendly: "Ah, that one again! A test still expects the old page count. Want me to update it and rerun everything?",
      pragmatic: "A test expects the old page count. Updating it and rerunning the suite.",
      neutral: "The failing test checks for the previous page count. I can update it if you’d like.",
    };
    const btn = $("[data-tone-btn]", tuner);
    const menu = $("[data-tone-menu]", tuner);
    const label = $("[data-tone-label]", tuner);
    const text = $("[data-tone-text]", tuner);
    const items = $$("[data-tone]", tuner);
    const hint = $(".tuner__hint", tuner);

    const close = () => { menu.hidden = true; btn.setAttribute("aria-expanded", "false"); };
    btn.addEventListener("click", () => {
      const opening = menu.hidden;
      menu.hidden = !opening;
      btn.setAttribute("aria-expanded", String(opening));
      if (opening) (items.find((i) => i.getAttribute("aria-checked") === "true") || items[0]).focus();
      if (hint) hint.remove();
    });
    document.addEventListener("click", (e) => { if (!e.target.closest(".tone")) close(); });
    menu.addEventListener("keydown", (e) => {
      const i = items.indexOf(document.activeElement);
      if (e.key === "Escape") { close(); btn.focus(); }
      if (e.key === "ArrowDown") { e.preventDefault(); items[(i + 1) % items.length].focus(); }
      if (e.key === "ArrowUp") { e.preventDefault(); items[(i + items.length - 1) % items.length].focus(); }
    });
    items.forEach((item) => item.addEventListener("click", async () => {
      items.forEach((x) => x.setAttribute("aria-checked", String(x === item)));
      label.textContent = item.textContent.trim();
      close();
      btn.focus();
      text.classList.add("fading");
      await sleep(220);
      text.textContent = TONES[item.dataset.tone];
      text.classList.remove("fading");
    }));

    $$("[data-preset]", tuner).forEach((p) => {
      const name = $("span", p);
      let before = "";
      const finish = (keep) => {
        if (!p.classList.contains("editing")) return;
        const value = name.textContent.replace(/\s+/g, " ").trim().slice(0, 18);
        name.textContent = keep && value ? value : before;
        name.contentEditable = "false";
        p.classList.remove("editing");
      };
      const start = () => {
        if (p.classList.contains("editing")) return;
        before = name.textContent;
        p.classList.add("editing");
        name.contentEditable = "true";
        name.focus();
        const range = document.createRange();
        range.selectNodeContents(name);
        const sel = getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      };
      p.addEventListener("click", start);
      p.addEventListener("keydown", (e) => {
        if (p.classList.contains("editing")) {
          if (e.key === "Enter") { e.preventDefault(); finish(true); p.focus(); }
          if (e.key === "Escape") { finish(false); p.focus(); }
        } else if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          start();
        }
      });
      name.addEventListener("blur", () => finish(true));
    });
  }

  /* Copy the build commands */
  const copyBtn = $("[data-copy]");
  if (copyBtn) {
    copyBtn.addEventListener("click", async () => {
      const label = $("span", copyBtn);
      const text = $(".code pre code").textContent.split("\n").filter((l) => l && !l.startsWith("#")).join("\n");
      try {
        await navigator.clipboard.writeText(text);
        label.textContent = "Copied";
        copyBtn.classList.add("copied");
      } catch {
        label.textContent = "Select and copy";
      }
      setTimeout(() => {
        label.textContent = "Copy";
        copyBtn.classList.remove("copied");
      }, 1800);
    });
  }
})();
