#pragma once

#include "ui/models/animation/AnimationCommands.hpp"
#include "ui/models/timeline/TimelineEditCommands.hpp"

namespace xyla {
using timeline::AddClipsCommand;
using timeline::BatchSlipCommand;
using timeline::BatchTrimCommand;
using timeline::DeleteClipsCommand;
using timeline::LinkClipsCommand;
using timeline::LockClipCommand;
using timeline::LockTrackCommand;
using timeline::MoveClipsCommand;
using timeline::MultiCutCommand;
using timeline::RippleMoveCommand;
using timeline::RollEditCommand;
using timeline::SelectClipsCommand;
using timeline::ThreePointEditCommand;
using timeline::UnlinkClipsCommand;

using anim::DeleteKeyframesCommand;
using anim::MoveKeyframesCommand;
using anim::PasteKeyframesCommand;
using anim::UpdateKeyframeCommand;
} // namespace xyla
