import math
import struct
import wave
import os
import random

def generate_instrumental_wave(filename, duration, notes, volume=0.5, instrument_type="koto"):
    sample_rate = 44100
    num_samples = int(duration * sample_rate)
    
    with wave.open(filename, 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sample_rate)
        
        for i in range(num_samples):
            t = float(i) / sample_rate
            val = 0.0
            
            for freq, start_time, note_vol in notes:
                if t < start_time: continue
                dt = t - start_time
                
                # Koto/Shamisen Timbre: Strong fundamental + non-harmonic overtones
                # Shamisen has a "buzzing" quality (Sawari)
                # Koto has a bright, metallic pluck
                
                # Base tone
                n_val = math.sin(2.0 * math.pi * freq * dt)
                # Overtones
                n_val += 0.5 * math.sin(2.0 * math.pi * freq * 2.0 * dt) # Octave
                n_val += 0.25 * math.sin(2.0 * math.pi * freq * 3.01 * dt) # Sharp 3rd harmonic
                n_val += 0.1 * math.sin(2.0 * math.pi * freq * 4.0 * dt)
                
                if instrument_type == "shamisen":
                    # Add "Sawari" buzz (slight distortion/noise)
                    buzz = (random.random() * 2.0 - 1.0) * 0.1 * math.exp(-20.0 * dt)
                    n_val += buzz
                
                # Sharp Pluck Envelope (Fast attack, rapid initial decay, long tail)
                attack = 0.005
                if dt < attack:
                    env = dt / attack
                else:
                    # Characteristic string decay
                    env = math.exp(-6.0 * dt / duration) * (1.0 / (1.0 + 10.0 * dt))
                
                val += n_val * note_vol * env

            final_val = val * volume
            final_val = max(-1.0, min(1.0, final_val))
            sample = int(final_val * 32767)
            f.writeframes(struct.pack('h', sample))

# 1. Move: Low Koto pluck (C3 ~130Hz)
generate_instrumental_wave('assets/sounds/move.wav', 0.4, [(130.81, 0.0, 1.0)], volume=0.6, instrument_type="koto")

# 2. Capture: Snappy Shamisen strike (higher tension)
generate_instrumental_wave('assets/sounds/capture.wav', 0.4, [(196.00, 0.0, 1.0)], volume=0.7, instrument_type="shamisen")

# 3. Promote: A very subtle, delicate Koto ripple (high harmonics)
promote_notes = [(1760, i*0.08, 0.4 - i*0.05) for i in range(4)]
generate_instrumental_wave('assets/sounds/promote.wav', 1.0, promote_notes, volume=0.15, instrument_type="koto")

# 4. Check: Resonant Koto Octave (A4 + A5)
generate_instrumental_wave('assets/sounds/check.wav', 1.0, [(440, 0.0, 1.0), (880, 0.0, 0.5)], volume=0.5, instrument_type="koto")

# 5. Checkmate: Solemn Shamisen sequence (Descending)
mate_notes = [(146.83, 0.0, 1.0), (110.00, 0.3, 0.8), (73.41, 0.7, 0.6)]
generate_instrumental_wave('assets/sounds/checkmate.wav', 2.0, mate_notes, volume=0.6, instrument_type="shamisen")

print("Traditional Japanese instrumental sound effects (Koto/Shamisen) generated.")
