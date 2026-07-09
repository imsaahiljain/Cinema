// Popcorn Feed — three exploratory feed scenes for the Popcorn app.
// Exports (CommonJS): FeedReel, FeedMarquee, FeedScreeningRoom

const DATA = [
  { id: 1, friend: 'Sofia Chen', hue: 18, time: '2h', movie: 'Past Lives', year: 2023, rating: 8.7,
    caption: "Cried on the subway home. Didn't expect that.", tags: ['Celine Song', 'A24'], likes: 12, comments: 3, ratio: 1.5 },
  { id: 2, friend: 'Marcus Webb', hue: 210, time: '4h', movie: 'Dune: Part Two', year: 2024, rating: 9.2,
    caption: 'IMAX was mandatory for this one. Sound alone is a 10.', tags: ['Denis Villeneuve', 'Sci-Fi'], likes: 34, comments: 8, ratio: 1.2 },
  { id: 3, friend: 'Priya Patel', hue: 275, time: '6h', movie: 'The Bear', year: 2024, rating: 7.8,
    caption: 'S3E1 — not as strong as season 1 but still good.', tags: ['TV', 'FX'], likes: 9, comments: 1, ratio: 1.8 },
  { id: 4, friend: 'Jordan Lee', hue: 340, time: '9h', movie: 'Anora', year: 2024, rating: 9.5,
    caption: "Palme d'Or well deserved. Rewatching this weekend.", tags: ['Sean Baker', 'Comedy'], likes: 41, comments: 12, ratio: 1.4 },
  { id: 5, friend: 'Ava Torres', hue: 40, time: '11h', movie: 'Twisters', year: 2024, rating: 6.4,
    caption: 'Popcorn movie, exactly what I wanted on a Friday.', tags: ['Action'], likes: 6, comments: 0, ratio: 1.3 },
  { id: 6, friend: 'Noah Kim', hue: 150, time: '1d', movie: 'The Zone of Interest', year: 2023, rating: 9.0,
    caption: 'Haunting. Still thinking about the sound design.', tags: ['Jonathan Glazer', 'Drama'], likes: 22, comments: 5, ratio: 1.6 },
  { id: 7, friend: 'Liam Ortiz', hue: 20, time: '1d', movie: 'Challengers', year: 2024, rating: 8.3,
    caption: 'That soundtrack lives in my head rent free.', tags: ['Luca Guadagnino'], likes: 28, comments: 6, ratio: 1.5 },
];

function initials(name) {
  return name.split(' ').map(w => w[0]).join('').slice(0, 2);
}

function Avatar({ name, hue, size = 36, ring }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%', flexShrink: 0,
      background: `oklch(0.62 0.11 ${hue})`,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: 'Manrope, sans-serif', fontWeight: 700, fontSize: size * 0.36,
      color: '#fff', boxShadow: ring ? `0 0 0 2px ${ring}` : 'none',
    }}>{initials(name)}</div>
  );
}

// subtle striped placeholder — stands in for a real poster image
function Poster({ hue, style, label = 'POSTER' }) {
  return (
    <div style={{
      position: 'relative', overflow: 'hidden',
      background: `repeating-linear-gradient(135deg, oklch(0.4 0.09 ${hue}), oklch(0.4 0.09 ${hue}) 10px, oklch(0.36 0.09 ${hue}) 10px, oklch(0.36 0.09 ${hue}) 20px)`,
      ...style,
    }}>
      <div style={{
        position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: 'ui-monospace, Menlo, monospace', fontSize: 9, letterSpacing: 1,
        color: 'rgba(255,255,255,0.55)', textAlign: 'center', padding: 6,
      }}>{label}</div>
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════
   1a — "Reel": dark, bold, immersive one-pop-per-screen, snap scroll
   ══════════════════════════════════════════════════════════════ */
function FeedReel() {
  const [liked, setLiked] = React.useState({});
  const toggleLike = (id) => setLiked(s => ({ ...s, [id]: !s[id] }));

  return (
    <div style={{
      height: '100%', overflowY: 'auto', scrollSnapType: 'y mandatory',
      background: '#160f0d', fontFamily: 'Manrope, sans-serif',
    }}>
      <div style={{
        position: 'sticky', top: 0, zIndex: 5, paddingTop: 52,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        pointerEvents: 'none',
      }}>
        <div style={{
          fontFamily: 'Bebas Neue, sans-serif', fontSize: 22, letterSpacing: 3,
          color: 'rgba(255,255,255,0.9)', textShadow: '0 2px 12px rgba(0,0,0,0.6)',
        }}>POPCORN</div>
      </div>
      {DATA.map(p => (
        <div key={p.id} style={{
          height: '100%', scrollSnapAlign: 'start', position: 'relative',
          display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
          marginTop: -52,
        }}>
          <Poster hue={p.hue} label="MOVIE STILL" style={{ position: 'absolute', inset: 0 }} />
          <div style={{
            position: 'absolute', inset: 0,
            background: 'linear-gradient(180deg, rgba(0,0,0,0.15) 0%, rgba(10,6,5,0.15) 45%, rgba(10,6,5,0.95) 100%)',
          }} />
          {/* rating stamp */}
          <div style={{
            position: 'absolute', top: 78, right: 20, zIndex: 2,
            width: 68, height: 68, borderRadius: '50%',
            border: '2.5px solid oklch(0.78 0.17 85)',
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
            transform: 'rotate(8deg)', background: 'rgba(10,6,5,0.35)', backdropFilter: 'blur(6px)',
          }}>
            <div style={{ fontFamily: 'Bebas Neue, sans-serif', fontSize: 26, color: 'oklch(0.85 0.15 85)', lineHeight: 1 }}>{p.rating}</div>
            <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 8, letterSpacing: 1.5, color: 'oklch(0.85 0.15 85)' }}>/ 10</div>
          </div>
          {/* content */}
          <div style={{ position: 'relative', zIndex: 2, padding: '0 20px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Avatar name={p.friend} hue={p.hue + 40} size={34} ring="oklch(0.72 0.19 40)" />
              <div>
                <div style={{ color: '#fff', fontWeight: 700, fontSize: 14 }}>{p.friend}</div>
                <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: 12 }}>{p.time} ago · popped</div>
              </div>
            </div>
            <div>
              <div style={{ fontFamily: 'Bebas Neue, sans-serif', fontSize: 42, letterSpacing: 1, color: '#fff', lineHeight: 1 }}>{p.movie}</div>
              <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: 13, marginTop: 4 }}>{p.year} · {p.tags.join(' · ')}</div>
            </div>
            <div style={{ color: 'rgba(255,255,255,0.85)', fontSize: 15, lineHeight: 1.4 }}>{p.caption}</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 18, marginTop: 4 }}>
              <button onClick={() => toggleLike(p.id)} style={{
                display: 'flex', alignItems: 'center', gap: 6, background: 'none', border: 'none',
                color: liked[p.id] ? 'oklch(0.72 0.19 40)' : 'rgba(255,255,255,0.75)',
                fontSize: 14, fontWeight: 700, padding: 0, cursor: 'pointer',
                transform: liked[p.id] ? 'scale(1.08)' : 'scale(1)', transition: 'transform 0.15s, color 0.15s',
              }}>
                <svg width="20" height="20" viewBox="0 0 24 24" fill={liked[p.id] ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2">
                  <path d="M12 21s-7.5-4.6-10-9.3C.5 8 2 4 6 4c2 0 3.5 1.2 4.5 2.7C11.5 5.2 13 4 15 4c4 0 5.5 4 4 7.7C19.5 16.4 12 21 12 21z"/>
                </svg>
                {p.likes + (liked[p.id] ? 1 : 0)}
              </button>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'rgba(255,255,255,0.75)', fontSize: 14, fontWeight: 700 }}>
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5H4l1.6-4.8A8.5 8.5 0 1 1 21 11.5z"/>
                </svg>
                {p.comments}
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════
   1b — "Marquee": warm, cozy, ticket-stub card feed
   ══════════════════════════════════════════════════════════════ */
function FeedMarquee() {
  const [open, setOpen] = React.useState({});
  const toggleOpen = (id) => setOpen(s => ({ ...s, [id]: !s[id] }));
  const bg = 'oklch(0.96 0.015 70)';

  return (
    <div style={{ height: '100%', overflowY: 'auto', background: bg, fontFamily: 'Nunito Sans, sans-serif' }}>
      <div style={{
        position: 'sticky', top: 0, zIndex: 5, background: bg, paddingTop: 56,
        paddingBottom: 12, paddingLeft: 20,
      }}>
        <div style={{ fontFamily: 'Libre Caslon Text, serif', fontSize: 30, color: 'oklch(0.32 0.03 40)' }}>Popcorn</div>
        <div style={{ fontSize: 12, color: 'oklch(0.5 0.02 40)', marginTop: 2 }}>What your friends are watching</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16, padding: '4px 16px 32px' }}>
        {DATA.map(p => (
          <div key={p.id} onClick={() => toggleOpen(p.id)} style={{
            display: 'flex', background: '#fff', borderRadius: 16, overflow: 'hidden',
            boxShadow: '0 1px 2px rgba(60,30,10,0.06), 0 6px 20px rgba(60,30,10,0.08)',
            cursor: 'pointer', position: 'relative',
          }}>
            <Poster hue={p.hue} label="POSTER" style={{ width: 96, flexShrink: 0 }} />
            {/* perforation */}
            <div style={{ position: 'relative', width: 0 }}>
              <div style={{ position: 'absolute', top: 0, bottom: 0, left: -1, width: 0, borderLeft: '2px dashed oklch(0.9 0.02 60)' }} />
              <div style={{ position: 'absolute', top: -6, left: -7, width: 14, height: 14, borderRadius: '50%', background: bg }} />
              <div style={{ position: 'absolute', bottom: -6, left: -7, width: 14, height: 14, borderRadius: '50%', background: bg }} />
            </div>
            <div style={{ flex: 1, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <Avatar name={p.friend} hue={p.hue + 40} size={22} />
                <div style={{ fontSize: 12.5, color: 'oklch(0.4 0.02 40)', fontWeight: 700 }}>{p.friend}</div>
                <div style={{ fontSize: 11.5, color: 'oklch(0.6 0.02 40)' }}>· {p.time}</div>
              </div>
              <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 8 }}>
                <div style={{ fontFamily: 'Libre Caslon Text, serif', fontSize: 19, color: 'oklch(0.25 0.02 40)', lineHeight: 1.15 }}>{p.movie}</div>
                <div style={{
                  flexShrink: 0, fontFamily: 'Libre Caslon Text, serif', fontSize: 15, fontWeight: 700,
                  color: '#fff', background: 'oklch(0.55 0.18 30)', borderRadius: 8, padding: '2px 8px',
                }}>{p.rating}</div>
              </div>
              <div style={{
                fontSize: 13.5, color: 'oklch(0.35 0.02 40)', lineHeight: 1.4,
                display: '-webkit-box', WebkitLineClamp: open[p.id] ? 'unset' : 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
              }}>{p.caption}</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, maxHeight: open[p.id] ? 40 : 0, overflow: 'hidden', transition: 'max-height 0.2s' }}>
                {p.tags.map(t => (
                  <div key={t} style={{
                    fontSize: 11, color: 'oklch(0.5 0.14 75)', background: 'oklch(0.94 0.05 85)',
                    borderRadius: 100, padding: '3px 9px', fontWeight: 600,
                  }}>{t}</div>
                ))}
              </div>
              <div style={{ display: 'flex', gap: 14, marginTop: 2 }}>
                <div style={{ fontSize: 12, color: 'oklch(0.5 0.02 40)', fontWeight: 600 }}>♥ {p.likes}</div>
                <div style={{ fontSize: 12, color: 'oklch(0.5 0.02 40)', fontWeight: 600 }}>💬 {p.comments}</div>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════
   1c — "Screening Room": clean, minimal, editorial poster grid
   ══════════════════════════════════════════════════════════════ */
function FeedScreeningRoom() {
  const [selected, setSelected] = React.useState(null);
  const [tab, setTab] = React.useState('following');
  const sel = DATA.find(p => p.id === selected);

  return (
    <div style={{ height: '100%', overflowY: 'auto', background: '#fff', fontFamily: 'Work Sans, sans-serif', position: 'relative' }}>
      <div style={{ position: 'sticky', top: 0, zIndex: 5, background: '#fff', paddingTop: 56, paddingBottom: 10 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', padding: '0 20px' }}>
          <div style={{ fontFamily: 'Space Grotesk, sans-serif', fontWeight: 700, fontSize: 22, color: '#141414' }}>Screening Room</div>
        </div>
        <div style={{ display: 'flex', gap: 4, padding: '12px 20px 0' }}>
          {['following', 'for you'].map(t => (
            <div key={t} onClick={() => setTab(t)} style={{
              fontSize: 13, fontWeight: 600, padding: '6px 14px', borderRadius: 100, cursor: 'pointer',
              background: tab === t ? '#141414' : '#f2f2f2',
              color: tab === t ? '#fff' : '#666', textTransform: 'capitalize',
            }}>{t}</div>
          ))}
        </div>
      </div>
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 3, padding: '10px 3px 24px',
      }}>
        {DATA.map((p, i) => (
          <div key={p.id} onClick={() => setSelected(p.id)} style={{
            position: 'relative', cursor: 'pointer', gridRow: i % 3 === 0 ? 'span 2' : 'span 1',
          }}>
            <Poster hue={p.hue} label="POSTER" style={{ width: '100%', height: '100%', aspectRatio: i % 3 === 0 ? '0.72' : '0.95' }} />
            <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, transparent 60%, rgba(0,0,0,0.55) 100%)' }} />
            <div style={{ position: 'absolute', top: 8, left: 8 }}>
              <Avatar name={p.friend} hue={p.hue + 40} size={24} ring="#fff" />
            </div>
            <div style={{
              position: 'absolute', top: 8, right: 8, background: 'oklch(0.85 0.16 95)', color: '#141414',
              fontFamily: 'Space Grotesk, sans-serif', fontWeight: 700, fontSize: 12, borderRadius: 6, padding: '2px 6px',
            }}>{p.rating}</div>
            <div style={{ position: 'absolute', bottom: 8, left: 8, right: 8, color: '#fff' }}>
              <div style={{ fontFamily: 'Space Grotesk, sans-serif', fontWeight: 600, fontSize: 13, lineHeight: 1.2 }}>{p.movie}</div>
              <div style={{ fontSize: 10.5, opacity: 0.8, marginTop: 1 }}>{p.friend}</div>
            </div>
          </div>
        ))}
      </div>

      {sel && (
        <div style={{ position: 'absolute', inset: 0, zIndex: 30 }}>
          <div onClick={() => setSelected(null)} style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.4)' }} />
          <div style={{
            position: 'absolute', left: 0, right: 0, bottom: 0, background: '#fff',
            borderRadius: '20px 20px 0 0', padding: '18px 20px 32px',
            display: 'flex', flexDirection: 'column', gap: 12,
            boxShadow: '0 -8px 30px rgba(0,0,0,0.2)',
          }}>
            <div style={{ width: 36, height: 4, borderRadius: 2, background: '#e0e0e0', alignSelf: 'center' }} />
            <div style={{ display: 'flex', gap: 12 }}>
              <Poster hue={sel.hue} label="POSTER" style={{ width: 64, height: 90, borderRadius: 8, flexShrink: 0 }} />
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: 'Space Grotesk, sans-serif', fontWeight: 700, fontSize: 19, color: '#141414' }}>{sel.movie}</div>
                <div style={{ fontSize: 12, color: '#888', marginTop: 2 }}>{sel.year} · {sel.tags.join(' · ')}</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8 }}>
                  <Avatar name={sel.friend} hue={sel.hue + 40} size={22} />
                  <div style={{ fontSize: 12.5, fontWeight: 600, color: '#333' }}>{sel.friend}</div>
                  <div style={{
                    marginLeft: 'auto', background: 'oklch(0.85 0.16 95)', color: '#141414', fontFamily: 'Space Grotesk, sans-serif',
                    fontWeight: 700, fontSize: 14, borderRadius: 6, padding: '2px 8px',
                  }}>{sel.rating}</div>
                </div>
              </div>
            </div>
            <div style={{ fontSize: 14, color: '#333', lineHeight: 1.5 }}>{sel.caption}</div>
            <div style={{ display: 'flex', gap: 16 }}>
              <div style={{ fontSize: 13, color: '#555', fontWeight: 600 }}>♥ {sel.likes} likes</div>
              <div style={{ fontSize: 13, color: '#555', fontWeight: 600 }}>💬 {sel.comments} comments</div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════
   2a — "The Bucket": friends as popcorn kernels — pop when they post
   ══════════════════════════════════════════════════════════════ */
const BUCKET_POPPED = [
  { id: 1, friend: 'Sofia', hue: 18, left: 190, top: 70, size: 76, rot: -8, movie: 'Past Lives', year: 2023, rating: 8.7, caption: "Cried on the subway home. Didn't expect that.", tags: ['Celine Song', 'A24'], likes: 12, comments: 3 },
  { id: 2, friend: 'Marcus', hue: 210, left: 300, top: 100, size: 86, rot: 7, movie: 'Dune: Part Two', year: 2024, rating: 9.2, caption: 'IMAX was mandatory for this one. Sound alone is a 10.', tags: ['Denis Villeneuve', 'Sci-Fi'], likes: 34, comments: 8 },
  { id: 3, friend: 'Priya', hue: 275, left: 130, top: 190, size: 64, rot: 12, movie: 'The Bear', year: 2024, rating: 7.8, caption: 'S3E1 — not as strong as season 1 but still good.', tags: ['TV', 'FX'], likes: 9, comments: 1 },
  { id: 4, friend: 'Jordan', hue: 340, left: 260, top: 202, size: 70, rot: -11, movie: 'Anora', year: 2024, rating: 9.5, caption: "Palme d'Or well deserved. Rewatching this weekend.", tags: ['Sean Baker', 'Comedy'], likes: 41, comments: 12 },
  { id: 5, friend: 'Ava', hue: 40, left: 90, top: 90, size: 60, rot: 15, movie: 'Twisters', year: 2024, rating: 6.4, caption: 'Popcorn movie, exactly what I wanted on a Friday.', tags: ['Action'], likes: 6, comments: 0 },
];
const BUCKET_UNPOPPED = [
  { id: 'u1', friend: 'Emma', hue: 300, left: 118, top: 302, size: 42 },
  { id: 'u2', friend: 'Tyler', hue: 60, left: 210, top: 322, size: 40 },
  { id: 'u3', friend: 'Zoe', hue: 190, left: 300, top: 296, size: 38 },
  { id: 'u4', friend: 'Ben', hue: 10, left: 155, top: 392, size: 38 },
  { id: 'u5', friend: 'Grace', hue: 130, left: 262, top: 394, size: 40 },
];

function FeedBucket() {
  const [selected, setSelected] = React.useState(null);
  const [shakeId, setShakeId] = React.useState(null);
  const sel = BUCKET_POPPED.find(p => p.id === selected);
  const bg = 'oklch(0.96 0.015 70)';

  const tapUnpopped = (id) => {
    setShakeId(id);
    setTimeout(() => setShakeId(null), 420);
  };

  return (
    <div style={{ height: '100%', overflow: 'hidden', background: bg, fontFamily: 'Nunito Sans, sans-serif', position: 'relative' }}>
      <style>{`
        @keyframes kernelShake { 0%,100%{ transform: translate(-50%,-50%) rotate(0deg); } 25%{ transform: translate(-56%,-50%) rotate(-6deg); } 75%{ transform: translate(-44%,-50%) rotate(6deg); } }
        @keyframes kernelPopIn { 0%{ transform: translate(-50%,-30%) scale(0.4); opacity: 0; } 60%{ transform: translate(-50%,-56%) scale(1.08); opacity: 1; } 100%{ transform: translate(-50%,-50%) scale(1); opacity: 1; } }
      `}</style>

      <div style={{ position: 'relative', zIndex: 2, paddingTop: 56, paddingBottom: 6, paddingLeft: 20 }}>
        <div style={{ fontFamily: 'Libre Caslon Text, serif', fontSize: 28, color: 'oklch(0.32 0.03 40)' }}>The Bucket</div>
        <div style={{ fontSize: 12.5, color: 'oklch(0.5 0.02 40)', marginTop: 2 }}>Tap a friend who's popped something</div>
      </div>

      <div style={{ position: 'relative', height: 500 }}>
        {/* bucket */}
        <div style={{
          position: 'absolute', left: 76, top: 176, width: 250, height: 300,
          clipPath: 'polygon(14% 0%, 86% 0%, 100% 100%, 0% 100%)',
          background: 'repeating-linear-gradient(90deg, oklch(0.55 0.18 30) 0 22px, oklch(0.97 0.01 70) 22px 44px)',
          boxShadow: '0 30px 50px rgba(60,20,10,0.18)',
        }}>
          <div style={{
            position: 'absolute', left: 0, right: 0, bottom: 22, textAlign: 'center',
          }}>
            <div style={{
              fontFamily: 'Libre Caslon Text, serif', fontSize: 22, letterSpacing: 2, color: '#fff',
              textShadow: '0 2px 6px rgba(0,0,0,0.25)',
            }}>POPCORN</div>
          </div>
        </div>
        {/* rim */}
        <div style={{
          position: 'absolute', left: 62, top: 160, width: 278, height: 40, borderRadius: '50%',
          background: 'oklch(0.55 0.18 30)', boxShadow: '0 4px 0 rgba(0,0,0,0.08)',
        }} />
        <div style={{
          position: 'absolute', left: 68, top: 164, width: 266, height: 32, borderRadius: '50%',
          background: 'oklch(0.97 0.01 70)',
        }} />

        {/* unpopped kernels — nestled in the cup */}
        {BUCKET_UNPOPPED.map(k => (
          <div key={k.id} onClick={() => tapUnpopped(k.id)} style={{
            position: 'absolute', left: k.left, top: k.top,
            transform: shakeId === k.id ? undefined : 'translate(-50%,-50%)',
            animation: shakeId === k.id ? 'kernelShake 0.4s ease' : undefined,
            cursor: 'pointer', zIndex: 3,
          }}>
            <div style={{
              width: k.size, height: k.size,
              borderRadius: '48% 52% 45% 55% / 58% 55% 45% 42%',
              background: 'linear-gradient(160deg, oklch(0.88 0.09 85), oklch(0.78 0.1 78))',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: '0 2px 5px rgba(90,60,10,0.2)',
            }}>
              <div style={{ filter: 'saturate(0.5) opacity(0.75)' }}>
                <Avatar name={k.friend} hue={k.hue} size={k.size * 0.6} />
              </div>
            </div>
            <div style={{
              position: 'absolute', top: k.size + 4, left: '50%', transform: 'translateX(-50%)',
              fontSize: 10, color: 'oklch(0.5 0.03 60)', whiteSpace: 'nowrap',
            }}>{k.friend}</div>
          </div>
        ))}

        {/* popped kernels — burst up out of the bucket */}
        {BUCKET_POPPED.map((k, i) => (
          <div key={k.id} onClick={() => setSelected(k.id)} style={{
            position: 'absolute', left: k.left, top: k.top,
            transform: 'translate(-50%,-50%)', zIndex: 4, cursor: 'pointer',
            animation: `kernelPopIn 0.5s cubic-bezier(.3,1.5,.4,1) ${i * 0.08}s both`,
          }}>
            <div style={{ position: 'relative', width: k.size, height: k.size, transform: `rotate(${k.rot}deg)` }}>
              <div style={{
                position: 'absolute', width: k.size * 0.66, height: k.size * 0.66, top: -k.size * 0.16, left: -k.size * 0.14,
                borderRadius: '52% 48% 55% 45% / 48% 55% 45% 52%', background: '#fffaf0',
                boxShadow: '0 2px 6px rgba(90,60,10,0.12)',
              }} />
              <div style={{
                position: 'absolute', width: k.size * 0.6, height: k.size * 0.6, bottom: -k.size * 0.14, right: -k.size * 0.12,
                borderRadius: '55% 45% 48% 52% / 45% 52% 48% 55%', background: '#fffaf0',
                boxShadow: '0 2px 6px rgba(90,60,10,0.12)',
              }} />
              <div style={{
                position: 'absolute', inset: 0, borderRadius: '50%',
                background: 'radial-gradient(circle at 32% 28%, #fffef8, #fdf3df)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                boxShadow: '0 3px 10px rgba(90,60,10,0.22)',
              }}>
                <Avatar name={k.friend} hue={k.hue + 30} size={k.size * 0.66} ring="#fff" />
              </div>
              <div style={{
                position: 'absolute', top: -2, right: -2, width: 12, height: 12, borderRadius: '50%',
                background: 'oklch(0.55 0.18 30)', border: '2px solid #fffaf0',
              }} />
            </div>
            <div style={{
              position: 'absolute', top: k.size + 4, left: '50%', transform: 'translateX(-50%) rotate(0deg)',
              fontSize: 11, fontWeight: 700, color: 'oklch(0.35 0.03 40)', whiteSpace: 'nowrap',
            }}>{k.friend}</div>
          </div>
        ))}
      </div>

      {sel && (
        <div style={{ position: 'absolute', inset: 0, zIndex: 30 }}>
          <div onClick={() => setSelected(null)} style={{ position: 'absolute', inset: 0, background: 'rgba(30,15,5,0.4)' }} />
          <div style={{
            position: 'absolute', left: 0, right: 0, bottom: 0, background: '#fffaf3',
            borderRadius: '20px 20px 0 0', padding: '18px 20px 32px',
            display: 'flex', flexDirection: 'column', gap: 12,
            boxShadow: '0 -8px 30px rgba(60,20,10,0.2)',
          }}>
            <div style={{ width: 36, height: 4, borderRadius: 2, background: 'oklch(0.85 0.02 60)', alignSelf: 'center' }} />
            <div style={{ display: 'flex', gap: 12 }}>
              <Poster hue={sel.hue} label="POSTER" style={{ width: 64, height: 90, borderRadius: 8, flexShrink: 0 }} />
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: 'Libre Caslon Text, serif', fontSize: 19, color: 'oklch(0.3 0.03 40)' }}>{sel.movie}</div>
                <div style={{ fontSize: 12, color: 'oklch(0.55 0.02 50)', marginTop: 2 }}>{sel.year} · {sel.tags.join(' · ')}</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8 }}>
                  <Avatar name={sel.friend} hue={sel.hue + 30} size={22} />
                  <div style={{ fontSize: 12.5, fontWeight: 700, color: 'oklch(0.35 0.02 40)' }}>{sel.friend}</div>
                  <div style={{
                    marginLeft: 'auto', fontFamily: 'Libre Caslon Text, serif', fontWeight: 700, fontSize: 15,
                    color: '#fff', background: 'oklch(0.55 0.18 30)', borderRadius: 8, padding: '2px 9px',
                  }}>{sel.rating}</div>
                </div>
              </div>
            </div>
            <div style={{ fontSize: 14, color: 'oklch(0.35 0.02 40)', lineHeight: 1.5 }}>{sel.caption}</div>
            <div style={{ display: 'flex', gap: 16 }}>
              <div style={{ fontSize: 13, color: 'oklch(0.5 0.02 40)', fontWeight: 600 }}>♥ {sel.likes} likes</div>
              <div style={{ fontSize: 13, color: 'oklch(0.5 0.02 40)', fontWeight: 600 }}>💬 {sel.comments} comments</div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

module.exports = { FeedReel, FeedMarquee, FeedScreeningRoom, FeedBucket };
