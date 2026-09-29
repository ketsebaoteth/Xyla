#pragma once

#include <QString>
#include <QStringList>
#include <cstdint>
#include <optional>
#include <vector>

namespace xyla::timeline {

/**
 * @brief Identifies the interactive tool or edit gesture currently driving a
 * timeline session.
 */
enum class InteractionMode {
  Idle,
  Move,
  RippleMove,
  TrimLeft,
  TrimRight,
  Roll,
  Slip,
  RippleTrimLeft,
  RippleTrimRight
};

/**
 * @brief Cached initial and active projected geometry for a clip participating
 * in a gesture.
 */
struct ParticipantClip {
  QString clipId;
  int initialTrackIndex{0};
  int64_t initialStartFrame{0};
  int64_t initialDurationFrames{0};
  int64_t initialSourceInFrame{0};

  int projectedTrackIndex{0};
  int64_t projectedStartFrame{0};
  int64_t projectedDurationFrames{0};
  int64_t projectedSourceInFrame{0};
};

/**
 * @brief Tracks and projects transient geometric states during live interactive
 * timeline gestures.
 *
 * Maintains reference snapshots of participant clips and computes provisional
 * layout coordinates during mouse tracking without committing persistent
 * modifications to the timeline model.
 *
 * @note Designed to isolate in-flight gesture calculations from the persistent
 * undo stack.
 */
class TimelineInteractionSession {
public:
  TimelineInteractionSession() = default;

  /**
   * @brief Initialize an active move gesture session across selected and linked
   * clips.
   *
   * @param leaderClipId Identifier of the primary clip receiving direct user
   * input.
   * @param participants Snapshots of all clips participating in the
   * translation.
   * @param ripple True if downstream tracks ripple during movement.
   */
  void beginMove(const QString &leaderClipId,
                 const std::vector<ParticipantClip> &participants, bool ripple);

  /**
   * @brief Initialize an active single-edge trim session for one or more linked
   * clips.
   *
   * @param leaderClipId Identifier of the clip whose edge is actively being
   * dragged.
   * @param participants Snapshots of participating clips.
   * @param trimLeft True for in-point head trimming; false for out-point tail
   * trimming.
   * @param ripple True to ripple downstream clips on the track.
   */
  void beginTrim(const QString &leaderClipId,
                 const std::vector<ParticipantClip> &participants,
                 bool trimLeft, bool ripple);

  /**
   * @brief Initialize a dual-clip roll edit session across an adjacent cut
   * boundary.
   *
   * @param leftClip Snapshot of the clip preceding the cut boundary.
   * @param rightClip Snapshot of the clip succeeding the cut boundary.
   * @param maxLeftFrames Maximum allowable leftward cut boundary shift.
   * @param maxRightFrames Maximum allowable rightward cut boundary shift.
   */
  void beginRoll(const ParticipantClip &leftClip,
                 const ParticipantClip &rightClip, int64_t maxLeftFrames,
                 int64_t maxRightFrames);

  /**
   * @brief Initialize an active slip edit session locking clip duration and
   * timeline position.
   *
   * @param participants Snapshots of all clips undergoing source in-point
   * shifting.
   * @param maxSourceDuration Maximum available source frames in the underlying
   * asset.
   */
  void beginSlip(const std::vector<ParticipantClip> &participants,
                 int64_t maxSourceDuration);

  /**
   * @brief Update projected participant coordinates using relative gesture
   * deltas.
   *
   * @param deltaFrames Horizontal frame offset relative to gesture initiation.
   * @param deltaTracks Vertical track lane offset relative to gesture
   * initiation.
   */
  void updateDelta(int64_t deltaFrames, int deltaTracks = 0);

  /**
   * @brief Terminate the active session and reset all cached participant
   * states.
   */
  void endSession();

  /**
   * @brief Retrieve projected state for a specific participating clip.
   *
   * @param clipId Identifier of the clip to locate.
   * @return Participant state if registered in current session; std::nullopt
   * otherwise.
   */
  [[nodiscard]] std::optional<ParticipantClip>
  getParticipant(const QString &clipId) const;

  [[nodiscard]] bool isActive() const noexcept {
    return m_mode != InteractionMode::Idle;
  }
  [[nodiscard]] InteractionMode mode() const noexcept { return m_mode; }
  [[nodiscard]] const QString &leaderClipId() const noexcept {
    return m_leaderClipId;
  }
  [[nodiscard]] const std::vector<ParticipantClip> &
  participants() const noexcept {
    return m_participants;
  }

private:
  InteractionMode m_mode{InteractionMode::Idle};
  QString m_leaderClipId;
  std::vector<ParticipantClip> m_participants;

  int64_t m_maxLeftRollFrames{0};
  int64_t m_maxRightRollFrames{0};
  int64_t m_maxSourceDuration{0};
};

} // namespace xyla::timeline
