/// Flat C-ABI command packet sent from Dart over the ring buffer.
///
/// ```text
/// kind  0  NoteOn          track_id  param_a=pitch   param_b=vel(0-127)  value=—
/// kind  1  NoteOff         track_id  param_a=pitch   —                   value=—
/// kind  2  SetVoiceParam   track_id  param_a=VoiceParam  —               value=f32
/// kind  3  SetBPM          —         —               —                   value=bpm
/// kind  4  SetTransport    —         param_a=0(stop)/1(play)/2(reset)    value=—
/// kind  5  SetStep         track_id  param_a=step_idx  param_b=pitch     value=vel(0=clear)
/// kind  6  SetEffect       track_id  param_a=EffectParam —               value=f32
/// kind  7  SetNumSteps     —         param_a=steps(8/16/32/64)           value=—
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

#[derive(Debug, Clone, Copy)]
pub enum Command {
    NoteOn        { track_id: u8, pitch: u8, velocity: f32 },
    NoteOff       { track_id: u8, pitch: u8 },
    SetVoiceParam { track_id: u8, param: VoiceParam, value: f32 },
    SetBPM        (f32),
    SetTransport  (TransportState),
    SetStep       { track_id: u8, step_idx: u8, pitch: u8, velocity: f32 },
    SetEffect     { track_id: u8, param: EffectParam, value: f32 },
    SetNumSteps   (usize),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum VoiceParam {
    OscType = 0, Attack = 1, Decay = 2, Sustain = 3,
    Release = 4, Volume = 5,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum EffectParam {
    ReverbSend = 0, DelayTime = 1, DelayFeedback = 2,
    DelaySend = 3, DistDrive = 4,
    ReverbRoom = 5, ReverbDamp = 6,
    FilterType = 7, FilterCutoff = 8, FilterResonance = 9,
}

#[derive(Debug, Clone, Copy)]
pub enum TransportState { Stop, Play, Reset }

impl FfiCommand {
    pub fn decode(self) -> Option<Command> {
        match self.kind {
            0 => Some(Command::NoteOn {
                track_id: self.track_id,
                pitch:    self.param_a,
                velocity: self.param_b as f32 / 127.0,
            }),
            1 => Some(Command::NoteOff { track_id: self.track_id, pitch: self.param_a }),
            2 => {
                let param = voice_param(self.param_a)?;
                Some(Command::SetVoiceParam { track_id: self.track_id, param, value: self.value })
            }
            3 => Some(Command::SetBPM(self.value)),
            4 => Some(Command::SetTransport(match self.param_a {
                1 => TransportState::Play,
                2 => TransportState::Reset,
                _ => TransportState::Stop,
            })),
            5 => Some(Command::SetStep {
                track_id: self.track_id,
                step_idx: self.param_a,
                pitch:    self.param_b,
                velocity: self.value,
            }),
            6 => {
                let param = effect_param(self.param_a)?;
                Some(Command::SetEffect { track_id: self.track_id, param, value: self.value })
            }
            7 => Some(Command::SetNumSteps(self.param_a as usize)),
            _ => None,
        }
    }
}

fn voice_param(v: u8) -> Option<VoiceParam> {
    Some(match v {
        0 => VoiceParam::OscType, 1 => VoiceParam::Attack, 2 => VoiceParam::Decay,
        3 => VoiceParam::Sustain, 4 => VoiceParam::Release, 5 => VoiceParam::Volume,
        _ => return None,
    })
}

fn effect_param(v: u8) -> Option<EffectParam> {
    Some(match v {
        0 => EffectParam::ReverbSend,    1 => EffectParam::DelayTime,
        2 => EffectParam::DelayFeedback, 3 => EffectParam::DelaySend,
        4 => EffectParam::DistDrive,     5 => EffectParam::ReverbRoom,
        6 => EffectParam::ReverbDamp,    7 => EffectParam::FilterType,
        8 => EffectParam::FilterCutoff,  9 => EffectParam::FilterResonance,
        _ => return None,
    })
}
