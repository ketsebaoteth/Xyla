#pragma once

#include <memory>
#include <vector>

#include <QJsonObject>
#include <QString>
#include <QStringList>

#include "core/timeline/timelineTrack.hpp"
#include "ui/models/timeline/TimelineTrackMetrics.hpp"
#include "ui/models/timelineLinkGraph.hpp"

namespace xyla::anim {
class AnimationManager;
}

namespace xyla::timeline {

/**
 * @brief Self-contained sequence containing its own tracks, link graph,
 * animation table, and view metrics.
 *
 * Encapsulates all state for an independent editing timeline tab, enabling
 * multiple open sequences within a single project session.
 *
 * @note Owned and orchestrated directly by TimelineModel.
 */
class TimelineSequence {
public:
  /**
   * @brief Construct an empty sequence with a unique identifier and display
   * name.
   *
   * @param id Unique sequence identifier.
   * @param name User-facing sequence name.
   */
  explicit TimelineSequence(QString id,
                            QString name = QStringLiteral("Sequence"));
  ~TimelineSequence() = default;

  TimelineSequence(const TimelineSequence &) = delete;
  TimelineSequence &operator=(const TimelineSequence &) = delete;
  TimelineSequence(TimelineSequence &&) noexcept = default;
  TimelineSequence &operator=(TimelineSequence &&) noexcept = default;

  /**
   * @brief Populate default video and audio tracks for a newly created
   * sequence.
   *
   * @param videoCount Number of video tracks to generate.
   * @param audioCount Number of audio tracks to generate.
   */
  void createDefaultTracks(int videoCount, int audioCount);

  /**
   * @brief Bind all clips contained in this sequence to an active animation
   * manager.
   *
   * @param animMgr Animation manager receiving clip table handles.
   */
  void bindAnimationManager(xyla::anim::AnimationManager &animMgr);

  [[nodiscard]] const QString &id() const noexcept { return m_id; }
  [[nodiscard]] const QString &name() const noexcept { return m_name; }
  void setName(QString name) { m_name = std::move(name); }

  [[nodiscard]] std::vector<std::shared_ptr<xyla::TimelineTrack>> &
  tracks() noexcept {
    return m_tracks;
  }
  [[nodiscard]] const std::vector<std::shared_ptr<xyla::TimelineTrack>> &
  tracks() const noexcept {
    return m_tracks;
  }

  [[nodiscard]] xyla::TimelineLinkGraph &linkGraph() noexcept {
    return m_linkGraph;
  }
  [[nodiscard]] const xyla::TimelineLinkGraph &linkGraph() const noexcept {
    return m_linkGraph;
  }

  [[nodiscard]] TimelineTrackMetrics &trackMetrics() noexcept {
    return m_trackMetrics;
  }
  [[nodiscard]] const TimelineTrackMetrics &trackMetrics() const noexcept {
    return m_trackMetrics;
  }

  [[nodiscard]] std::shared_ptr<xyla::anim::AnimationPropertyTable>
  animationTable() const noexcept {
    return m_animationTable;
  }

  [[nodiscard]] double zoomFactor() const noexcept { return m_zoomFactor; }
  void setZoomFactor(double factor) noexcept { m_zoomFactor = factor; }

  [[nodiscard]] double horizontalOffset() const noexcept {
    return m_horizontalOffset;
  }
  void setHorizontalOffset(double offset) noexcept {
    m_horizontalOffset = offset;
  }

  [[nodiscard]] bool snappingEnabled() const noexcept {
    return m_snappingEnabled;
  }
  void setSnappingEnabled(bool enabled) noexcept {
    m_snappingEnabled = enabled;
  }

  [[nodiscard]] bool globalRippleMode() const noexcept {
    return m_globalRippleMode;
  }
  void setGlobalRippleMode(bool enabled) noexcept {
    m_globalRippleMode = enabled;
  }

  [[nodiscard]] const QStringList &selectedClipIds() const noexcept {
    return m_selectedClipIds;
  }
  void setSelectedClipIds(QStringList ids) {
    m_selectedClipIds = std::move(ids);
  }

  [[nodiscard]] const QString &selectedClipId() const noexcept {
    return m_selectedClipId;
  }
  void setSelectedClipId(QString id) { m_selectedClipId = std::move(id); }

  [[nodiscard]] int selectedTrackIndex() const noexcept {
    return m_selectedTrackIndex;
  }
  void setSelectedTrackIndex(int index) noexcept {
    m_selectedTrackIndex = index;
  }

  /**
   * @brief Serialize the complete sequence state, tracks, clips, and view
   * parameters.
   *
   * @return Serialized JSON object.
   */
  [[nodiscard]] QJsonObject serialize() const;

  /**
   * @brief Deserialize a sequence instance from a JSON object.
   *
   * @param obj Serialized sequence JSON object.
   * @param animMgr Optional animation manager to re-bind loaded clips.
   * @return Instantiated sequence pointer, or nullptr on corrupt data.
   */
  [[nodiscard]] static std::unique_ptr<TimelineSequence>
  deserialize(const QJsonObject &obj,
              xyla::anim::AnimationManager *animMgr = nullptr);

private:
  QString m_id;
  QString m_name;

  std::vector<std::shared_ptr<xyla::TimelineTrack>> m_tracks;
  xyla::TimelineLinkGraph m_linkGraph;
  TimelineTrackMetrics m_trackMetrics;
  std::shared_ptr<xyla::anim::AnimationPropertyTable> m_animationTable;

  QString m_selectedClipId;
  QStringList m_selectedClipIds;
  int m_selectedTrackIndex{-1};

  double m_zoomFactor{1.0};
  double m_horizontalOffset{0.0};
  bool m_snappingEnabled{true};
  bool m_globalRippleMode{false};
};

} // namespace xyla::timeline
