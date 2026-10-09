(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const sleep = (ms) => new Promise((r) => setTimeout(r, reduce ? 0 : ms));

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

  // Call enter/leave as el scrolls in and out (for loops that should pause off screen).
  function whileVisible(el, enter, leave, threshold = 0.3) {
    if (!el) return;
    new IntersectionObserver((entries) => {
      for (const e of entries) (e.isIntersecting ? enter : leave)();
    }, { threshold }).observe(el);
  }

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
  const COLORS = ["#ff7a45", "#ff4d8d", "#ffd23f", "#3ddc97", "#7da8ff", "#f4f4f5"];
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

  function burst(x, y, count = 90, palette = COLORS) {
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

  /* Floating hero tiles drift a little with the pointer */
  const hero = $(".hero");
  const tiles = $$(".tile");
  if (hero && tiles.length && !reduce && matchMedia("(pointer: fine)").matches) {
    let px = 0, py = 0, frame = 0;
    hero.addEventListener("pointermove", (e) => {
      const r = hero.getBoundingClientRect();
      px = (e.clientX - r.left) / r.width - 0.5;
      py = (e.clientY - r.top) / r.height - 0.5;
      if (!frame) frame = requestAnimationFrame(applyDrift);
    });
    hero.addEventListener("pointerleave", () => {
      px = py = 0;
      if (!frame) frame = requestAnimationFrame(applyDrift);
    });
    function applyDrift() {
      frame = 0;
      for (const t of tiles) {
        const depth = parseFloat(t.style.getPropertyValue("--depth")) || 1;
        t.style.setProperty("--px", `${(-px * 28 * depth).toFixed(1)}px`);
        t.style.setProperty("--py", `${(-py * 20 * depth).toFixed(1)}px`);
      }
    }
  }

  /* Hero story: Claude works, you steer, it lands */
  const story = $("[data-story]");
  if (story) {
    const steps = $$("[data-step]", story);
    const rows = $$(".steps__row", story);
    const checks = $$("[data-check]", story);
    const tag = $("[data-steer-tag]", story);
    const stream = $("[data-stream]", story);
    const field = $(".composer__field", story);
    const typed = $("[data-type-target]", story);
    const send = $(".composer__send", story);
    const spinner = $("[data-story-spin]", story);
    const replay = $("[data-replay]", story);
    const reply = stream.textContent.trim();
    const steerText = "also make the button throw confetti";
    let run = 0;

    const step = (n) => steps.find((s) => s.dataset.step === String(n)).classList.add("on");
    const check = (item) => {
      item.classList.add("done");
      item.querySelector("i").className = "ph-fill ph-check-circle";
    };

    function reset() {
      steps.forEach((s) => s.classList.remove("on"));
      rows.forEach((r) => r.classList.remove("on"));
      checks.forEach((c) => {
        c.classList.remove("done");
        c.querySelector("i").className = "ph ph-circle";
      });
      tag.textContent = "Queued";
      tag.classList.remove("sent");
      stream.textContent = "";
      typed.textContent = "";
      field.classList.remove("typing");
      send.classList.remove("hot");
      spinner.classList.remove("done");
      replay.classList.remove("show");
    }

    function finalState() {
      steps.forEach((s) => s.classList.add("on"));
      rows.forEach((r) => r.classList.add("on"));
      checks.forEach(check);
      tag.textContent = "Sent while working";
      tag.classList.add("sent");
      stream.textContent = reply;
      spinner.classList.add("done");
    }

    async function play() {
      const me = ++run;
      const wait = async (ms) => {
        await sleep(ms);
        if (me !== run) throw new Error("cancelled");
      };
      reset();
      try {
        await wait(450);
        step(1);
        await wait(700);
        step(2);
        for (const r of rows) {
          await wait(420);
          r.classList.add("on");
        }
        await wait(450);
        step(3);
        await wait(650);
        check(checks[0]);

        // You think of something mid-turn and just send it.
        await wait(400);
        field.classList.add("typing");
        for (const ch of steerText) {
          typed.textContent += ch;
          await wait(34 + Math.random() * 40);
        }
        await wait(300);
        send.classList.add("hot");
        await wait(180);
        typed.textContent = "";
        field.classList.remove("typing");
        send.classList.remove("hot");
        step(4);

        await wait(900);
        check(checks[1]);
        await wait(500);
        tag.textContent = "Sent while working";
        tag.classList.add("sent");
        await wait(700);
        check(checks[2]);

        await wait(500);
        step(5);
        const words = reply.split(" ");
        for (let i = 0; i < words.length; i++) {
          stream.textContent += (i ? " " : "") + words[i];
          await wait(38 + Math.random() * 50);
        }
        spinner.classList.add("done");
        await wait(600);
        replay.classList.add("show");
      } catch {
        /* a replay started; the new run owns the window now */
      }
    }

    if (reduce) {
      finalState();
    } else {
      reset();
      onVisible(story, play, 0.25);
      replay.addEventListener("click", play);
    }
  }

  /* Claude <-> Codex handoff */
  const handoff = $("[data-handoff]");
  if (handoff) {
    const log = $("[data-handoff-log]", handoff);
    const btn = $("[data-handoff-btn]", handoff);
    const btnLabel = $("span", btn);
    const pillMark = $("[data-agent-mark]", handoff);
    const pillName = $("[data-agent-name]", handoff);
    const placeholder = $("[data-handoff-ph]", handoff);
    const lines = {
      codex: {
        divider: "Switched to Codex. It read the whole chat first.",
        reply: "Caught up. I’ll update the test and rerun the suite.",
        next: "Hand it back to Claude",
        colors: ["#7da8ff", "#f4f4f5", "#3ddc97"],
      },
      claude: {
        divider: "Back to Claude. Nothing was lost.",
        reply: "Thanks, Codex. Tests are green, so I’ll open the pull request.",
        next: "Hand it to Codex",
        colors: ["#ff7a45", "#ffd23f", "#ff4d8d"],
      },
    };
    let busy = false;

    function add(node) {
      log.append(node);
      while (log.children.length > 6) log.firstElementChild.remove();
    }

    btn.addEventListener("click", async () => {
      if (busy) return;
      busy = true;
      const to = handoff.dataset.agent === "claude" ? "codex" : "claude";
      const copy = lines[to];
      const markClass = to === "codex" ? "mark--openai" : "mark--claude";
      const name = to === "codex" ? "Codex" : "Claude";

      handoff.dataset.agent = to;
      pillMark.className = `mark ${markClass}`;
      pillName.textContent = name;
      placeholder.textContent = `Message ${name}`;
      burstFrom(btn, 36, copy.colors);

      const divider = document.createElement("div");
      divider.className = "handoff__divider";
      divider.textContent = copy.divider;
      add(divider);

      await sleep(650);
      const msg = document.createElement("div");
      msg.className = "msg msg--agent enter";
      msg.innerHTML = `<span class="mark ${markClass}"></span><p></p>`;
      msg.querySelector("p").textContent = copy.reply;
      add(msg);

      btnLabel.textContent = copy.next;
      busy = false;
    });
  }

  /* Bento: steering states loop while on screen */
  const steerDemo = $("[data-steer-demo]");
  if (steerDemo) {
    const steerTag = $("[data-steer-demo-tag]", steerDemo);
    let timer = 0;
    const cycle = () => {
      const sent = steerTag.classList.toggle("sent");
      steerTag.textContent = sent ? "Sent while working" : "Queued";
      timer = setTimeout(cycle, sent ? 2600 : 1600);
    };
    if (reduce) {
      steerTag.classList.add("sent");
      steerTag.textContent = "Sent while working";
    } else {
      whileVisible(steerDemo, () => { if (!timer) timer = setTimeout(cycle, 1200); }, () => { clearTimeout(timer); timer = 0; });
    }
  }

  /* Bento: the plan ticks itself off */
  const planDemo = $("[data-plan-demo]");
  onVisible(planDemo, async () => {
    for (const item of $$("[data-check]", planDemo)) {
      await sleep(700);
      item.classList.add("done");
      item.querySelector("i").className = "ph-fill ph-check-circle";
    }
  }, 0.5);

  /* Bento: context ring fills */
  const ringDemo = $("[data-ring-demo]");
  onVisible(ringDemo, () => {
    const ring = $("[data-ring-target]", ringDemo);
    ring.style.setProperty("--p", ring.dataset.ringTarget);
  }, 0.5);

  /* Bento: Cmd-K types a search */
  const kDemo = $("[data-k-demo]");
  onVisible(kDemo, async () => {
    const out = $("[data-k-type]", kDemo);
    for (const ch of "cheek") {
      await sleep(140);
      out.textContent += ch;
    }
  }, 0.5);

  /* Phone: a notification, then an approval you can actually tap */
  const phone = $("[data-phone]");
  if (phone) {
    const approval = $("[data-approval]", phone);
    const done = $("[data-approved]", phone);
    onVisible(phone, async () => {
      await sleep(400);
      phone.classList.add("notified");
      await sleep(1500);
      phone.classList.add("asking");
    }, 0.45);

    $("[data-allow]", phone).addEventListener("click", (e) => {
      approval.classList.add("answered");
      approval.classList.remove("denied");
      done.innerHTML = '<i class="ph-fill ph-check-circle" aria-hidden="true"></i> Approved from your phone.';
      burstFrom(e.currentTarget, 70);
    });
    $("[data-deny]", phone).addEventListener("click", () => {
      approval.classList.add("answered", "denied");
      done.innerHTML = '<i class="ph ph-hand-palm" aria-hidden="true"></i> Denied. Claude will think of another way.';
    });
  }

  /* Terminal types the build */
  const term = $("[data-term]");
  if (term) {
    const body = $("[data-term-body]", term);
    const commands = [
      ["~/code", "git clone --recursive https://github.com/shelbyklein/chatterbox"],
      ["~/code", "cd chatterbox"],
      ["~/code/chatterbox", "xcodegen generate"],
      ["~/code/chatterbox", "xcodebuild -scheme Chatterbox build"],
    ];
    const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
    const comment = '<span class="t-dim"># needs Xcode, plus xcodegen (brew install xcodegen)</span>\n';
    const prompt = (dir) => `<span class="t-prompt">${dir} $</span> `;
    const success = '<span class="t-ok">** BUILD SUCCEEDED **</span>';

    if (reduce) {
      body.innerHTML = comment + commands.map(([d, c]) => prompt(d) + esc(c)).join("\n") + "\n" + success;
    } else {
      body.innerHTML = '<span class="t-caret"></span>';
      onVisible(term, async () => {
        let html = comment;
        for (const [dir, cmd] of commands) {
          html += prompt(dir);
          for (let i = 1; i <= cmd.length; i++) {
            body.innerHTML = html + esc(cmd.slice(0, i)) + '<span class="t-caret"></span>';
            await sleep(cmd.length > 30 ? 14 : 38);
          }
          html += esc(cmd) + "\n";
          body.innerHTML = html + '<span class="t-caret"></span>';
          await sleep(380);
        }
        body.innerHTML = html + success + "\n" + prompt("~/code/chatterbox") + '<span class="t-caret"></span>';
      }, 0.4);
    }

    const copyBtn = $("[data-copy]", term);
    copyBtn.addEventListener("click", async () => {
      const label = $("span", copyBtn);
      try {
        await navigator.clipboard.writeText(commands.map(([, c]) => c).join("\n"));
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

  /* Reviews: duplicate each row once so the marquee loops seamlessly */
  for (const row of $$(".marquee__row")) {
    for (const card of [...row.children]) {
      const clone = card.cloneNode(true);
      clone.setAttribute("aria-hidden", "true");
      row.append(clone);
    }
  }
})();
