Server.default.options.numInputBusChannels_(5);

(
~input = 4;

Server.default.options.device_("ASIO");
// Server.default.options.blockSize_(32);
Server.default.options.memSize_(2**20);

s.waitForBoot({

	b = Buffer.alloc(s, 4 * s.sampleRate);
	~fast_buf = Buffer.alloc(s, 0.01 * s.sampleRate);

	SynthDef(\rec,{RecordBuf.ar(SoundIn.ar(~input), b)}).play;
	SynthDef(\recFast, {RecordBuf.ar(SoundIn.ar(~input), ~fast_buf)}).play;

	SynthDef(\grains, {
		arg amp = 0.4;
		var tRate, dur, clk, scan, position, pan, envNumSegs, env, sig;
		tRate = 32;
		dur = 12/tRate;
		clk = Impulse.kr(tRate);
		//scan = LFNoise1.kr(1).range(-1, 1);
		scan = LFNoise1.kr(0.07).range(0.02, BufDur.ir(b) - 0.02);
		position = scan + (TRand.kr(0, 0.01, clk));
		pan = WhiteNoise.kr(0.6);
		env = EnvGen.kr(
			Env(([0] ++ Rand(0.0, 1.0) ++ [1, 0]),
				{ExpRand(3, 8)}!3,
				{IRand(-20, 20)}!3
			),
			doneAction:2);
		sig = TGrains.ar(2, clk, b, 1, position, dur, pan, 0.5);
		sig = Limiter.ar(sig);
		Out.ar(0,
			amp * env * sig);
	}).add;

	~grains = {
		loop {
			Synth(\grains);
			rrand(7, 12).wait;
		}
	}.fork;

	// ~grains.stop;

	~fft_buf1 = Buffer.alloc(s, 2**17);
	~fft_buf2 = Buffer.alloc(s, 2**15);
	~fft_buf3 = Buffer.alloc(s, 2**8);

	h = SynthDef(\magNoise, {
		var source, chain, sig, amp;
		source = PlayBuf.ar(1, b,
			[ Demand.kr(Dust.kr(0.15), 0, Dseq([1, 0.5, -1, -0.5], inf)),
				SinOsc.kr(0.11).range(0.98, 1.03) ],
			loop:1);
		chain = FFT([~fft_buf1, ~fft_buf2], source);
		chain = PV_MagNoise(chain);
		chain = IFFT(chain);
		sig = Splay.ar(chain, SinOsc.kr(0.13).range);
		sig = FreeVerb2.ar(sig[0], sig[1], mix:0.5);
		amp = SinOsc.kr(0.2).range(0.8, 1.2);
		Out.ar(0, sig * amp);
	}).play;


	// h.free;



	SynthDef(\magNoiseFast, {
		arg amp = 1.5;
		var source, chain, sig, filterFreq, env;
		source = PlayBuf.ar(1, ~fast_buf, loop:1);
		chain = FFT(~fft_buf3, source);
		chain = PV_MagNoise(chain);
		chain = IFFT(chain);
		filterFreq = 300 + Demand.kr(Dust.kr(0.22), 0, Diwhite(-100, 700));
		sig = LPF18.ar(chain, filterFreq, LFNoise1.kr(1.5).range(0.3, 0.91));
		sig = sig * LFPulse.kr(LFTri.kr(0.1).range(0.2, 10), width:0.2);
		sig = FreeVerb.ar(sig, mix:0.3);
		sig = Pan2.ar(sig, SinOsc.kr(0.13));
		env = Env.linen(1.8, 2, 5.0).kr(Done.freeSelf);
		Out.ar(0, sig * env * amp);
	}).add;



	~magNoiseFast = {
		loop {
			rrand(9, 18).wait;
			Synth(\magNoiseFast);
		}
	}.fork;


	// ~magNoiseFast.stop;


	SynthDef(\feedbackFM, {
		arg amp = 1.6;
		var in, inFreq, hasFreq, maxSpeed, freq, rangeMin, rangeMax, mod, car, sig, control, env;
		control = LFGauss.ar(4, 0.1);
		in = SoundIn.ar(~input);
		# inFreq, hasFreq = Pitch.kr(in);
		maxSpeed = LFNoise1.kr(1).range(2, 8);
		freq = inFreq + (WhiteNoise.ar(100) * control);
		rangeMin = LFPulse.kr([0.8, 1.3]).range([0.5, 1], [2, 3]);
		rangeMax = LFPulse.kr([0.2, 0.6]).range(3.9, 4.1);
		mod = SinOscFB.ar(freq*LFPulse.kr(LFNoise1.kr([0.7, 1.1]).range(0.3, 1.2)).range(rangeMin, rangeMax));

		car = SinOscFB.ar(freq + mod, (LFNoise1.kr(LFNoise1.kr([0.4, 0.23, 0.69], 0.5, 0.8)).range(0.2*pi, 0.9*pi)));
		sig = RLPF.ar(car, LFNoise0.kr(LinLin.kr(control, dstlo:0.2)).range(400, 2000));
		sig = sig * Amplitude.kr(in, 0.01, 0.9) * 1.5;
		//sig = sig * Lag.kr(hasFreq, 0.1);
		sig = FreeVerb.ar(sig, mix:0.7);
		sig = Splay.ar(sig, LFNoise1.kr(1).range(0.1, 1));
		env = EnvGen.kr(
			Env(levels:[0, 1].lace(11),
				times:[0.01, Rand(0.0, 3.0)] ++
				Array.fill(7, {Rand(0.001, 0.5)}) ++
				[ExpRand(1, 8)],
				curve:[\hold] ++ {IRand(-20, 20)}!9 ++ [\sin]),
			doneAction:2);
		Out.ar(0, sig * env * amp);
	}).add;

	~feedbackFM = {
		loop {
			rrand(5, 15).wait;
			Synth(\feedbackFM);
		}
	}.fork;


	// ~feedbackFM.stop;


	SynthDef(\ping, {
		arg freq;
		var sig, env, amp;
		sig = BLowPass4.ar(SinOsc.ar([freq, freq * 1.03]), Rand(350, 1800), [1, 0.7]);
		env = Env.perc(0.001, 1, curve:-4).kr(Done.freeSelf);
		amp = Amplitude.ar(PlayBuf.ar(1, b, loop:1), 0.01, 0.7) * 1.3;
		Out.ar(0, sig * env * amp);
	}).add;

	f = {
		loop {
			4.do {
				Synth(\ping, [freq: 38.midicps]);
				1.wait;
				Synth(\ping, [freq: 40.midicps]);
				4.5.wait;
			};
			6.wait;
			Synth(\ping, [freq: 50.midicps]);
			0.33.wait;
			Synth(\ping, [freq: 52.midicps]);
			4.wait;
			2.do {
				Synth(\ping, [freq: 38.midicps]);
				0.75.wait;
				Synth(\ping, [freq: 40.midicps]);
				1.wait;
				Synth(\ping, [freq: 41.midicps]);
				3.wait;
			};
			Synth(\ping, [freq: 57.midicps]);
			0.33.wait;
			Synth(\ping, [freq: 50.midicps]);
			0.33.wait;
			Synth(\ping, [freq: 52.midicps]);
			4.wait;
		}
	}.fork;


	// f.stop;


	SynthDef(\tremNoise, {
		var source, env, trem, sig, amp = 0.2;
		source = Mix.new([SoundIn.ar(~input), PlayBuf.ar(1, b, loop:1)]);
		env = Env.perc(3, 2).kr(Done.freeSelf) * Amplitude.ar(source, 0.01, 0.9);
		trem = LFPulse.ar(XLine.kr(4, 10, 4), width:WhiteNoise.kr.range(0.05, 0.6));
		sig = WhiteNoise.ar(0.1);
		sig = Ringz.ar(sig, SinOsc.kr(0.2).range(100, 200), LFPar.kr(0.9).range(0.2, 0.9));
		sig = Pan2.ar(sig, LFTri.kr(0.5).range(-0.7, 0.7));
		Out.ar(0, FreeVerb.ar(sig * trem * env * amp));
	}).add;

	~tremNoise = {
		loop {
			rrand(10, 23).wait;
			Synth(\tremNoise);
		}
	}.fork;


	// ~tremNoise.free;


	SynthDef(\waves, {
		var noise, motion, hps, wave, sig, env, amp = 1.8;
		noise = WhiteNoise.ar(0.04 + LFNoise1.kr(0.3, 0.03));
		motion = LFNoise1.kr(0.2).exprange(100, 2000);
		hps = HPF.ar(noise.value, 50);
		wave = LPF.ar(hps.value, motion.value).tanh;
		sig = wave!10;
		sig = Splay.ar(sig, 0.9).tanh;
		env = Env.linen(3, 1, 5, curve:\sin).kr(Done.freeSelf);
		Out.ar(0, LeakDC.ar(sig * env * amp));
	}).add;


	~waves = {
		loop {
			rrand(11, 22).wait;
			~fast_buf.getn(0, 100, {
				arg x;
				if (x.top.abs > 0.001, {
					Synth(\waves)
				},{
					"waves: buffer silent".postln;
					x.postln;
				})
			});
		}
	}.fork;


	// ~waves.free;

});
)