/// Flat C-ABI-compatible command packet sent from Dart via the FFI.
///
/// ```text
/// kind     : 0 = NoteOn  | 1 = NoteOff  | 2 = SetVoiceParam
/// track_id : 0..7
/// param_a  : pitch (NoteOn/Off) | VoiceParam id (SetVoiceParam)
/// param_b  : velocity 0..127 (NoteOn) | unused
/// value    : parameter value (SetVoiceParam) | unused
/// ```
#[derive(Debug, Clone, Copy)]
#[repr(C)]
pub struct FfiCommand {
    pub kind:     u8,
    pub track_id: u8,
    pub param_a:  u8,
    pub param_b:  u8,
    pub value:    f32,
}

/// Decoded command used internally by the audio thread.
#[derive(Debug, Clone, Copy)]
pub enum Command {
    NoteOn  { track_id: u8, pitch: u8, velocity: f32 },
    NoteOff { track_id: u8, pitch: u8 },
    SetVoiceParam { track_id: u8, param: VoiceParam, value: f32 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum VoiceParam {
    OscType   = 0,
    Attack    = 1,
    Decay     = 2,
    Sustain   = 3,
    Release   = 4,
    Cutoff    = 5,
    Resonance = 6,
    Volume    = 7,
}

impl FfiCommand {
    pub fn decode(self) -> Option<Command> {
        match self.kind {
            0 => Some(Command::NoteOn {
                track_id: self.track_id,
                pitch:    self.param_a,
                velocity: self.param_b as f32 / 127.0,
            }),
            1 => Some(Command::NoteOff {
                track_id: self.track_id,
                pitch:    self.param_a,
            }),
            2 => {
                let param = match self.param_a {
                    0 => VoiceParam::OscType,
                    1 => VoiceParam::Attack,
                    2 => VoiceParam::Decay,
                    3 => VoiceParam::Sustain,
                    4 => VoiceParam::Release,
                    5 => VoiceParam::Cutoff,
                    6 => VoiceParam::Resonance,
                    7 => VoiceParam::Volume,
                    _ => return None,
                };
                Some(Command::SetVoiceParam {
                    track_id: self.track_id,
                    param,
                    value: self.value,
                })
            }
            _ => None,
        }
    }
}
