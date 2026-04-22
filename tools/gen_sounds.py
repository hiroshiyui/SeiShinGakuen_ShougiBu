import math
import struct
import wave
import os
import random

def generate_elegant_tuplet(filename, duration, notes, volume=0.5, instrument_type="koto"):
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
                
                # Base tone + Harmonics
                n_val = math.sin(2.0 * math.pi * freq * dt)
                n_val += 0.4 * math.sin(2.0 * math.pi * freq * 2.01 * dt)
                n_val += 0.2 * math.sin(2.0 * math.pi * freq * 3.0 * dt)
                
                if instrument_type == "shamisen":
                    # Snappier attack and slight buzz
                    n_val += (random.random() * 2.0 - 1.0) * 0.05 * math.exp(-40.0 * dt)
                    decay_rate = 12.0
                else:
                    # Softer Koto decay
                    decay_rate = 8.0
                
                # Elegant Envelope
                attack = 0.004
                if dt < attack:
                    env = dt / attack
                else:
                    env = math.exp(-decay_rate * dt)
                
                val += n_val * note_vol * env

            final_val = val * volume
            # Soft clipping
            final_val = max(-1.0, min(1.0, final_val))
            sample = int(final_val * 32767)
            f.writeframes(struct.pack('h', sample))

# 1. Move: A slightly higher but still warm and subtle Koto doublet
move_notes = [(164.81, 0.0, 0.4), (246.94, 0.08, 0.2)] # E3 -> B3
generate_elegant_tuplet('assets/sounds/move.wav', 0.5, move_notes, volume=0.2, instrument_type="koto")

# 2. Capture: A warm Shamisen doublet at lower frequency
cap_notes = [(110.0, 0.0, 1.0), (146.83, 0.08, 0.8)] # A2 -> D3
generate_elegant_tuplet('assets/sounds/capture.wav', 0.5, cap_notes, volume=0.35, instrument_type="shamisen")

# 3. Promote: A very warm, low Koto triplet ripple
prom_notes = [(98.0, 0.0, 0.4), (130.81, 0.07, 0.3), (164.81, 0.14, 0.2)] # G2 -> C3 -> E3
generate_elegant_tuplet('assets/sounds/promote.wav', 1.0, prom_notes, volume=0.2, instrument_type="koto")

# 4. Check: A deep, resonant Koto tuplet
check_notes = [(82.41, 0.0, 0.8), (110.0, 0.1, 0.6), (82.41, 0.25, 0.5)] # E2 -> A2 -> E2
generate_elegant_tuplet('assets/sounds/check.wav', 1.2, check_notes, volume=0.4, instrument_type="koto")

# 5. Checkmate: A solemn Shamisen/Koto phrase (descending)
mate_notes = [(220, 0.0, 0.8), (164.81, 0.2, 0.7), (110, 0.5, 0.6)] # A3 -> E3 -> A2
generate_elegant_tuplet('assets/sounds/checkmate.wav', 2.0, mate_notes, volume=0.5, instrument_type="shamisen")

print("Subtle tuplet-based Japanese instrumental sounds generated.")
