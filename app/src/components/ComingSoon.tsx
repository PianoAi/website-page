import React, { useEffect, useRef, useState } from "react";

interface TimeLeft {
  d: string;
  h: string;
  m: string;
  s: string;
}

export default function ComingSoon() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [timeLeft, setTimeLeft] = useState<TimeLeft>({
    d: "--",
    h: "--",
    m: "--",
    s: "--",
  });

  useEffect(() => {
    const target = new Date();
    target.setDate(target.getDate() + 30);

    const tick = () => {
      const diff = target.getTime() - new Date().getTime();
      if (diff <= 0) return;

      const d = Math.floor(diff / 86400000);
      const h = Math.floor((diff % 86400000) / 3600000);
      const m = Math.floor((diff % 3600000) / 60000);
      const s = Math.floor((diff % 60000) / 1000);

      setTimeLeft({
        d: String(d).padStart(2, "0"),
        h: String(h).padStart(2, "0"),
        m: String(m).padStart(2, "0"),
        s: String(s).padStart(2, "0"),
      });
    };

    tick();
    const interval = setInterval(tick, 1000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let W: number, H: number;
    let animationFrameId: number;

    const resize = () => {
      W = canvas.width = canvas.offsetWidth;
      H = canvas.height = canvas.offsetHeight;
    };
    resize();
    window.addEventListener("resize", resize);

    const particles = Array.from({ length: 120 }, () => ({
      x: Math.random(),
      y: Math.random(),
      r: Math.random() * 1.2 + 0.2,
      a: Math.random(),
      speed: Math.random() * 0.0002 + 0.00005,
    }));

    const orbs = [
      { x: 0.2, y: 0.3, r: 220, c: "124,58,237", phase: 0, speed: 0.003 },
      { x: 0.8, y: 0.6, r: 180, c: "6,182,212", phase: 2, speed: 0.004 },
      { x: 0.5, y: 0.8, r: 150, c: "245,158,11", phase: 4, speed: 0.0025 },
    ];

    const draw = () => {
      ctx.clearRect(0, 0, W, H);

      orbs.forEach((o) => {
        o.phase += o.speed;
        const cx = (o.x + Math.sin(o.phase) * 0.12) * W;
        const cy = (o.y + Math.cos(o.phase * 0.7) * 0.1) * H;
        const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, o.r);
        g.addColorStop(0, `rgba(${o.c},0.18)`);
        g.addColorStop(1, `rgba(${o.c},0)`);
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(cx, cy, o.r, 0, Math.PI * 2);
        ctx.fill();
      });

      particles.forEach((p) => {
        p.a += p.speed;
        if (p.a > 1) p.a = 0;
        const alpha = Math.sin(p.a * Math.PI) * 0.8;
        ctx.beginPath();
        ctx.arc(p.x * W, p.y * H, p.r, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(255,255,255,${alpha})`;
        ctx.fill();
      });

      animationFrameId = requestAnimationFrame(draw);
    };

    draw();

    return () => {
      window.removeEventListener("resize", resize);
      cancelAnimationFrame(animationFrameId);
    };
  }, []);

  return (
    <div className="relative min-h-150 h-screen flex flex-col items-center justify-center overflow-hidden bg-background font-sans">
      {/* Canvas */}
      <canvas ref={canvasRef} className="absolute inset-0 w-full h-full z-0" />

      <div className="relative z-10 text-center p-8 max-w-160 w-full">
        {/* Badge */}
        <div className="inline-block text-[11px] font-semibold tracking-[0.2em] uppercase text-accent-cyan border border-accent-cyan/40 px-4 py-1.5 rounded-full mb-8 backdrop-blur-md bg-accent-cyan/5">
          Coming Soon
        </div>

        {/* Title */}
        <h1 className="text-[clamp(2.5rem,8vw,4.5rem)] font-extrabold leading-[1.05] tracking-tight mb-5 bg-linear-to-br from-white via-[#a78bfa] to-accent-cyan bg-clip-text text-transparent">
          From First Note
          <br />
          To Full Song
        </h1>

        {/* Subtitle */}
        <p className="text-base text-secondary leading-relaxed mb-10 max-w-100 mx-auto">
          Learning piano doesn't have to be daunting. We're building a friendly,
          interactive space for beginners to fall in love with music.
        </p>

        <div className="flex gap-4 justify-center mb-10">
          <TimeUnit value={timeLeft.d} label="Days" />
          <span className="text-2xl text-primary/50 font-light leading-18 self-start pb-5">
            :
          </span>
          <TimeUnit value={timeLeft.h} label="Hours" />
          <span className="text-2xl text-primary/50 font-light leading-18 self-start pb-5">
            :
          </span>
          <TimeUnit value={timeLeft.m} label="Mins" />
          <span className="text-2xl text-primary/50 font-light leading-18 self-start pb-5">
            :
          </span>
          <TimeUnit value={timeLeft.s} label="Secs" />
        </div>

        <div className="flex gap-1.5 justify-center mt-8">
          <div className="w-1.5 h-1.5 rounded-full bg-primary/40 animate-pulse-dot"></div>
          <div className="w-1.5 h-1.5 rounded-full bg-accent-cyan/40 animate-pulse-dot [animation-delay:0.3s]"></div>
          <div className="w-1.5 h-1.5 rounded-full bg-accent-amber/40 animate-pulse-dot [animation-delay:0.6s]"></div>
        </div>
      </div>
    </div>
  );
}

function TimeUnit({ value, label }: { value: string; label: string }) {
  return (
    <div className="flex flex-col items-center gap-1">
      <div className="text-[2.5rem] font-bold font-mono text-white bg-primary/12 border border-primary/25 rounded-xl w-18 h-18 flex items-center justify-center backdrop-blur-md relative overflow-hidden before:absolute before:inset-0 before:bg-linear-to-br before:from-primary/15 before:to-transparent">
        <span className="relative z-10">{value}</span>
      </div>
      <div className="text-[10px] font-medium tracking-[0.12em] uppercase text-secondary mt-1">
        {label}
      </div>
    </div>
  );
}
