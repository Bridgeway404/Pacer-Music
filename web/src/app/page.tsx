export default function Home() {
  return (
    <main className="min-h-screen bg-[#0a0d17] text-white flex items-center justify-center p-8">
      <div className="max-w-xl space-y-6">
        <p className="text-sm font-bold tracking-[0.3em] text-emerald-400">PACER</p>
        <h1 className="text-4xl font-black">Your run has a rhythm.</h1>
        <p className="text-white/70">
          Pacer is a native iOS app: it measures your running cadence and matches the
          music to it — following you in Follow Me mode, or leading you in Pace Me mode.
        </p>
        <p className="text-white/50 text-sm">
          This <code>/web</code> tree is the TypeScript reference implementation of the
          Pacer engines (cadence smoothing, BPM matching, sequencing) with its Vitest
          suite — the executable behavioral spec for the Swift package{" "}
          <code>ios/PacerKit</code>. The product lives in the <code>ios/</code>{" "}
          directory of this repository.
        </p>
      </div>
    </main>
  );
}
