#include "TimelineInteractionSession.hpp"

#include <algorithm>

namespace xyla::timeline {

void TimelineInteractionSession::beginMove(
    const QString &leaderClipId,
    const std::vector<ParticipantClip> &participants, bool ripple) {
  m_mode = ripple ? InteractionMode::RippleMove : InteractionMode::Move;
  m_leaderClipId = leaderClipId;
  m_participants = participants;
}

void TimelineInteractionSession::beginTrim(
    const QString &leaderClipId,
    const std::vector<ParticipantClip> &participants, bool trimLeft,
    bool ripple) {
  if (trimLeft) {
    m_mode =
        ripple ? InteractionMode::RippleTrimLeft : InteractionMode::TrimLeft;
  } else {
    m_mode =
        ripple ? InteractionMode::RippleTrimRight : InteractionMode::TrimRight;
  }

  m_leaderClipId = leaderClipId;
  m_participants = participants;
}

void TimelineInteractionSession::beginRoll(const ParticipantClip &leftClip,
                                           const ParticipantClip &rightClip,
                                           int64_t maxLeftFrames,
                                           int64_t maxRightFrames) {
  m_mode = InteractionMode::Roll;
  m_leaderClipId = leftClip.clipId;
  m_participants = {leftClip, rightClip};
  m_maxLeftRollFrames = maxLeftFrames;
  m_maxRightRollFrames = maxRightFrames;
}

void TimelineInteractionSession::beginSlip(
    const std::vector<ParticipantClip> &participants,
    int64_t maxSourceDuration) {
  m_mode = InteractionMode::Slip;
  m_leaderClipId = participants.empty() ? "" : participants.front().clipId;
  m_participants = participants;
  m_maxSourceDuration = maxSourceDuration;
}

void TimelineInteractionSession::updateDelta(int64_t deltaFrames,
                                             int deltaTracks) {
  if (m_mode == InteractionMode::Idle) {
    return;
  }

  switch (m_mode) {
  case InteractionMode::Move:
  case InteractionMode::RippleMove: {
    // find leader initial track to isolate track shifts to matching lanes
    int leaderTrack = -1;
    for (const auto &part : m_participants) {
      if (part.clipId == m_leaderClipId) {
        leaderTrack = part.initialTrackIndex;
        break;
      }
    }

    for (auto &part : m_participants) {
      part.projectedStartFrame =
          std::max<int64_t>(0, part.initialStartFrame + deltaFrames);
      // keep linked clips on separate track types from jumping lanes
      const int effectiveDeltaTracks =
          (leaderTrack == -1 || part.initialTrackIndex == leaderTrack)
              ? deltaTracks
              : 0;
      part.projectedTrackIndex =
          std::max(0, part.initialTrackIndex + effectiveDeltaTracks);
    }
    break;
  }

  case InteractionMode::TrimLeft:
  case InteractionMode::RippleTrimLeft: {
    for (auto &part : m_participants) {
      const int64_t maxDelta = part.initialDurationFrames - 1;
      const int64_t boundedDelta = std::min(deltaFrames, maxDelta);

      part.projectedStartFrame =
          std::max<int64_t>(0, part.initialStartFrame + boundedDelta);
      part.projectedDurationFrames =
          std::max<int64_t>(1, part.initialDurationFrames - boundedDelta);
      part.projectedSourceInFrame =
          std::max<int64_t>(0, part.initialSourceInFrame + boundedDelta);
    }
    break;
  }

  case InteractionMode::TrimRight:
  case InteractionMode::RippleTrimRight: {
    for (auto &part : m_participants) {
      part.projectedDurationFrames =
          std::max<int64_t>(1, part.initialDurationFrames + deltaFrames);
    }
    break;
  }

  case InteractionMode::Roll: {
    if (m_participants.size() < 2) {
      break;
    }

    const int64_t clampedDelta =
        std::clamp(deltaFrames, -m_maxLeftRollFrames, m_maxRightRollFrames);

    m_participants[0].projectedDurationFrames =
        m_participants[0].initialDurationFrames + clampedDelta;

    m_participants[1].projectedStartFrame =
        m_participants[1].initialStartFrame + clampedDelta;
    m_participants[1].projectedDurationFrames =
        m_participants[1].initialDurationFrames - clampedDelta;
    m_participants[1].projectedSourceInFrame =
        m_participants[1].initialSourceInFrame + clampedDelta;
    break;
  }

  case InteractionMode::Slip: {
    for (auto &part : m_participants) {
      const int64_t candidateIn = part.initialSourceInFrame - deltaFrames;
      if (m_maxSourceDuration > 0) {
        const int64_t maxIn = std::max<int64_t>(
            0, m_maxSourceDuration - part.initialDurationFrames);
        part.projectedSourceInFrame =
            std::clamp(candidateIn, static_cast<int64_t>(0), maxIn);
      } else {
        part.projectedSourceInFrame = std::max<int64_t>(0, candidateIn);
      }
    }
    break;
  }

  case InteractionMode::Idle:
    break;
  }
}

void TimelineInteractionSession::endSession() {
  m_mode = InteractionMode::Idle;
  m_leaderClipId.clear();
  m_participants.clear();
  m_maxLeftRollFrames = 0;
  m_maxRightRollFrames = 0;
  m_maxSourceDuration = 0;
}

std::optional<ParticipantClip>
TimelineInteractionSession::getParticipant(const QString &clipId) const {
  for (const auto &part : m_participants) {
    if (part.clipId == clipId) {
      return part;
    }
  }
  return std::nullopt;
}

} // namespace xyla::timeline
