#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <QAbstractListModel>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "core/actions/xylaActionManager.hpp"
#include "core/timeline/timelineClip.hpp"
#include "core/timeline/timelineTrack.hpp"
#include "core/undo/xylaUndoStack.hpp"
#include "project/projectManager.hpp"
#include "ui/models/timeline/TimelineEditCommands.hpp"
#include "ui/models/timeline/TimelineInteractionSession.hpp"
#include "ui/models/timeline/TimelineSequence.hpp"
#include "ui/snapEngine.hpp"

namespace xyla {
class TimelineCompositor;
/**
 * @brief Primary model and coordinator managing timeline sequences, tracks,
 * clips, and edit sessions.
 *
 * Exposes a stable QAbstractListModel interface to QtQuick representing the
 * currently active sequence, while owning multiple open sequences, coordinating
 * animation tables, and dispatching atomic undo commands.
 *
 * @note Manages sequence switching by resetting track rows and notifying the
 * active animation manager.
 */
class TimelineModel : public QAbstractListModel {
  Q_OBJECT

  Q_PROPERTY(int trackCount READ trackCount NOTIFY trackCountChanged)
  Q_PROPERTY(double zoomFactor READ getZoomFactor WRITE setZoomFactor NOTIFY
                 zoomFactorChanged)
  Q_PROPERTY(double horizontalOffset READ getHorizontalOffset WRITE
                 setHorizontalOffset NOTIFY horizontalOffsetChanged)
  Q_PROPERTY(bool snappingEnabled READ getSnappingEnabled WRITE
                 setSnappingEnabled NOTIFY snappingEnabledChanged)
  Q_PROPERTY(bool globalRippleMode READ getGlobalRippleMode WRITE
                 setGlobalRippleMode NOTIFY globalRippleModeChanged)
  Q_PROPERTY(QString selectedClipId READ getSelectedClipId WRITE
                 setSelectedClipId NOTIFY selectedClipIdChanged)
  Q_PROPERTY(QStringList selectedClipIds READ getSelectedClipIds NOTIFY
                 selectedClipsChanged)
  Q_PROPERTY(int selectedTrackIndex READ getSelectedTrackIndex WRITE
                 setSelectedTrackIndex NOTIFY selectedTrackIndexChanged)
  Q_PROPERTY(
      int totalTracksHeight READ totalTracksHeight NOTIFY trackMetricsChanged)
  Q_PROPERTY(QString activeSequenceId READ activeSequenceId NOTIFY
                 activeSequenceChanged)
  Q_PROPERTY(QString activeSequenceName READ activeSequenceName WRITE
                 setActiveSequenceName NOTIFY activeSequenceChanged)
  Q_PROPERTY(
      QVariantList sequenceList READ sequenceList NOTIFY sequenceListChanged)

public:
  enum TimelineRoles {
    TrackIdRole = Qt::UserRole + 1,
    TrackNameRole,
    TrackKindRole,
    TrackLockedRole,
    TrackMutedRole,
    TrackSelectedRole,
    TrackHeightRole
  };
  Q_ENUM(TimelineRoles)

  explicit TimelineModel(ProjectManager *projectManager = nullptr,
                         MediaPool *mediaPool = nullptr,
                         XylaUndoStack *undoStack = nullptr,
                         QObject *parent = nullptr);
  ~TimelineModel() override = default;

  int rowCount(const QModelIndex &parent = QModelIndex()) const override;
  QVariant data(const QModelIndex &index,
                int role = Qt::DisplayRole) const override;
  QHash<int, QByteArray> roleNames() const override;

  void registerActions(XylaActionManager *actionMgr,
                       PlaybackManager *playbackMgr);

  // sequence tab management
  [[nodiscard]] QString activeSequenceId() const noexcept;
  [[nodiscard]] QString activeSequenceName() const noexcept;
  void setActiveSequenceName(const QString &name);
  [[nodiscard]] QVariantList sequenceList() const;

  [[nodiscard]] ProjectManager *projectManager() noexcept {
    return m_projectManager;
  }
  [[nodiscard]] const ProjectManager *projectManager() const noexcept {
    return m_projectManager;
  }
  [[nodiscard]] XylaUndoStack *undoStack() const noexcept {
    return m_undoStack;
  }
  void setPlaybackManagerP(PlaybackManager *playbackManagerP) noexcept {
    m_playbackManager = playbackManagerP;
  }
  void setTimelineCompositor(TimelineCompositor *compositor) noexcept {
    m_timelineCompositor = compositor;
  }
  [[nodiscard]] TimelineCompositor *timelineCompositor() const noexcept {
    return m_timelineCompositor;
  }

  // track and sequence clearing
  void addTrack(std::shared_ptr<TimelineTrack> track);
  void clearTimeline();
  /**
   * @brief Create and append a new sequence tab to the project.
   *
   * @param name Optional display label assigned to the sequence.
   * @return Unique identifier of the created sequence.
   */
  Q_INVOKABLE QString createSequence(const QString &name = QString());

  /**
   * @brief Remove an existing sequence tab from the project.
   *
   * @param sequenceId Identifier of the sequence to remove.
   * @return True if removed; false if not found or if attempting to remove the
   * last sequence.
   * @note Preserves at least one active sequence in the model.
   */
  Q_INVOKABLE bool deleteSequence(const QString &sequenceId);

  /**
   * @brief Switch the active timeline view to display a different sequence.
   *
   * Swaps tracks, link graphs, track metrics, and active animation property
   * tables.
   *
   * @param sequenceId Identifier of the sequence to activate.
   * @return True if switch succeeded; false if sequence does not exist.
   */
  Q_INVOKABLE bool switchSequence(const QString &sequenceId);

  /**
   * @brief Switch active sequence by zero-based list index.
   *
   * @param index Sequence index in the open tabs collection.
   * @return True if switched; false if index is out of range.
   */
  Q_INVOKABLE bool switchSequenceByIndex(int index);

  // track metrics and vertical geometry
  [[nodiscard]] int totalTracksHeight() const noexcept;
  Q_INVOKABLE int getTrackHeight(int trackIndex) const noexcept;
  Q_INVOKABLE void setTrackHeight(int trackIndex, int height);
  Q_INVOKABLE int getTrackY(int trackIndex) const noexcept;
  Q_INVOKABLE int getTrackAtY(int canvasY) const noexcept;

  // track administration
  Q_INVOKABLE void addVideoTrack();
  Q_INVOKABLE void addAudioTrack();
  Q_INVOKABLE void createDefaultTracks(int videoCount, int audioCount);
  Q_INVOKABLE int getTrackKind(int trackIndex) const;
  Q_INVOKABLE bool isTrackLocked(int trackIndex) const;
  Q_INVOKABLE void setTrackLocked(int trackIndex, bool locked);
  Q_INVOKABLE void toggleTrackLock(int trackIndex);
  Q_INVOKABLE bool isTrackMuted(int trackIndex) const;
  Q_INVOKABLE void setTrackMuted(int trackIndex, bool muted);
  Q_INVOKABLE void toggleTrackMute(int trackIndex);
  Q_INVOKABLE void selectTrack(int trackIndex);

  // native spatial queries and collision resolution
  Q_INVOKABLE QJsonObject resolvePlacement(const QStringList &clipIds,
                                           int64_t desiredStartFrame,
                                           int targetTrackIndex,
                                           int64_t originFrame, int originTrack,
                                           int64_t lastValidFrame,
                                           int lastValidTrack) const;

  Q_INVOKABLE QVariantMap querySnap(int64_t candidateStart, int64_t duration,
                                    int targetTrack, int64_t playheadFrame,
                                    double zoomFactor,
                                    const QStringList &ignoreClipIds,
                                    double snapPixelThreshold = 8.0) const;

  // clip lifecycle and editing
  Q_INVOKABLE QString addClip(const QString &assetId, const QString &name,
                              int trackIndex, int64_t startFrame,
                              int64_t durationFrames,
                              int64_t sourceInFrame = 0);

  Q_INVOKABLE QString addTitleClip(int trackIndex, int64_t startFrame,
                                   int64_t durationFrames,
                                   const QString &text = "Title");
  Q_INVOKABLE QString addSvgClip(const QString &filePath, int trackIndex,
                                 int64_t startFrame, int64_t durationFrames);
  Q_INVOKABLE bool removeClip(const QString &clipId, int trackIndex = -1);
  Q_INVOKABLE bool razorCut(int64_t cutFrame, int targetTrack = -1);
  Q_INVOKABLE bool cutClip(const QString &clipId, int64_t frame);
  Q_INVOKABLE bool cutAtPlayhead(int64_t playheadFrame);

  // transforms: move, trim, roll, slip
  Q_INVOKABLE bool moveClip(const QString &clipId, int fromTrack, int toTrack,
                            int64_t newStartFrame);
  Q_INVOKABLE bool moveClips(const QStringList &clipIds, int64_t deltaFrames,
                             int deltaTracks);
  Q_INVOKABLE bool rippleMoveClip(const QString &clipId, int toTrack,
                                  int64_t dropFrame, bool global);
  Q_INVOKABLE bool trimClip(const QString &clipId, int trackIndex,
                            int64_t newStart, int64_t newDur, int64_t newIn,
                            bool isRipple);
  Q_INVOKABLE bool rollEdit(const QString &leftClipId,
                            const QString &rightClipId, int64_t splitFrame);
  Q_INVOKABLE bool slipClip(const QString &clipId, int64_t newSourceInFrame);
  Q_INVOKABLE bool rippleTrimToPlayhead(int64_t playheadFrame, bool trimIn);

  // 3-point editing
  Q_INVOKABLE bool insertClip(const QString &assetId, int64_t sourceIn,
                              int64_t sourceOut, int64_t playheadFrame,
                              int targetTrack);
  Q_INVOKABLE bool overwriteClip(const QString &assetId, int64_t sourceIn,
                                 int64_t sourceOut, int64_t playheadFrame,
                                 int targetTrack);

  // selection and linking
  Q_INVOKABLE void selectClip(const QString &clipId, bool toggle, bool isRange);
  Q_INVOKABLE void selectBox(int64_t startFrame, int64_t endFrame,
                             int startTrack, int endTrack, bool toggle);
  Q_INVOKABLE void selectAll();
  Q_INVOKABLE void clearSelection();
  Q_INVOKABLE void deleteSelectedClips(bool ripple = false);
  Q_INVOKABLE bool canLinkSelection() const;
  Q_INVOKABLE bool canUnlinkSelection() const;
  Q_INVOKABLE void linkSelectedClips();
  Q_INVOKABLE void unlinkSelectedClips();
  Q_INVOKABLE bool isClipLocked(const QString &clipId) const;
  Q_INVOKABLE void setClipLocked(const QString &clipId, bool locked);
  Q_INVOKABLE void toggleClipLock(const QString &clipId);

  // interaction sessions for live multi-clip previews
  Q_INVOKABLE void beginInteraction(const QString &leaderClipId, int mode,
                                    int64_t maxLimit = 0);
  Q_INVOKABLE void updateInteraction(int64_t deltaFrames, int deltaTracks = 0);
  Q_INVOKABLE void endInteraction(bool commit);
  Q_INVOKABLE double getProjectedStart(const QString &clipId) const;
  Q_INVOKABLE double getProjectedDuration(const QString &clipId) const;
  Q_INVOKABLE double getProjectedSourceIn(const QString &clipId) const;
  Q_INVOKABLE int getProjectedTrack(const QString &clipId) const;

  // queries and lookups
  [[nodiscard]] std::vector<TimelineClip *>
  getSelectedClips(const ClipTypeFilter &filter) const;
  [[nodiscard]] TimelineClip *findClip(const QString &clipId);
  [[nodiscard]] const TimelineClip *findClip(const QString &clipId) const;
  [[nodiscard]] TimelineTrack *getTrack(int index) const noexcept;
  Q_INVOKABLE QString getAdjacentClipId(const QString &clipId,
                                        bool searchLeft) const;
  Q_INVOKABLE QStringList getLinkedClipIds(const QString &clipId) const;
  Q_INVOKABLE QVariantList getAllClips() const;
  Q_INVOKABLE QVariantList getClipsForTrack(int trackIndex) const;
  Q_INVOKABLE QVariantMap getSelectedClipData() const;
  Q_INVOKABLE int64_t getAssetDuration(const QString &assetId) const;
  Q_INVOKABLE QVariantList getClipWaveformPeaks(const QString &assetId,
                                                int64_t startFrame,
                                                int64_t durationFrames,
                                                int targetPixels) const;
  Q_INVOKABLE qint64 getDurationFrames() const;

  [[nodiscard]] std::shared_ptr<anim::AnimationPropertyTable>
  animationTable() const noexcept;
  [[nodiscard]] anim::AnimationManager *animationManager() const noexcept {
    return m_animationManager.get();
  }

  // direct undo targets
  void applyDirectAdd(TimelineClip clip, int trackIndex);
  void applyDirectRemove(const QString &clipId, int trackIndex);
  void applyDirectMove(const QString &clipId, int srcTrack, int dstTrack,
                       int64_t newStart);
  void applyDirectTrim(const QString &clipId, int trackIndex, int64_t start,
                       int64_t dur, int64_t in, bool isRipple, bool global,
                       bool isUndo = false);
  void applyDirectCut(const QString &clipId, int trackIndex, int64_t cutFrame,
                      const QString &newRightId,
                      const QString &newRightGroupId);
  void applyDirectUncut(const QString &leftClipId, int trackIndex,
                        const QString &rightClipId);
  void applyDirectSelection(const QStringList &selection);
  void applyDirectClipLock(const QString &clipId, bool locked);
  void applyDirectTrackLock(int trackIndex, bool locked);
  void applyDirectLink(const QStringList &clipIds, const QString &groupId);
  void applyDirectRestoreLinkGroups(
      const std::vector<std::pair<QString, QString>> &groups);
  void applyDirectRippleMove(const QString &clipId, int srcTrack, int dstTrack,
                             int64_t dropFrame, bool global,
                             int64_t &outOriginalStart,
                             QString &outSplitRightId);
  void applyDirectUndoRippleMove(const QString &clipId, int srcTrack,
                                 int dstTrack, int64_t dropFrame, bool global,
                                 int64_t originalStart,
                                 const QString &splitRightId);

  void notifyTimelineChanged(int trackA, int trackB = -1);
  void markDirty();
  void shiftAllTracksAfter(int64_t fromFrame, int64_t deltaFrames,
                           const QString &ignoreClipId);

  [[nodiscard]] size_t trackCount() const noexcept;
  [[nodiscard]] double getZoomFactor() const noexcept;
  void setZoomFactor(double factor);
  [[nodiscard]] double getHorizontalOffset() const noexcept;
  void setHorizontalOffset(double offset);
  [[nodiscard]] bool getSnappingEnabled() const noexcept;
  void setSnappingEnabled(bool enabled);
  [[nodiscard]] bool getGlobalRippleMode() const noexcept;
  void setGlobalRippleMode(bool enabled);
  [[nodiscard]] QString getSelectedClipId() const noexcept;
  void setSelectedClipId(const QString &clipId);
  [[nodiscard]] QStringList getSelectedClipIds() const noexcept;
  [[nodiscard]] int getSelectedTrackIndex() const noexcept;
  void setSelectedTrackIndex(int trackIndex);

  QJsonObject serialize() const;
  void deserialize(const QJsonObject &obj);

signals:
  void waveformReady(const QString &assetId);
  void trackCountChanged();
  void trackMetricsChanged();
  void zoomFactorChanged(double factor);
  void horizontalOffsetChanged(double offset);
  void snappingEnabledChanged(bool enabled);
  void globalRippleModeChanged(bool enabled);
  void selectedClipIdChanged(const QString &clipId);
  void selectedClipsChanged(const QStringList &clipIds);
  void selectedClipDataChanged();
  void selectedTrackIndexChanged(int trackIndex);
  void clipPropertiesChanged(const QString &clipId);
  void trackDataChanged(int trackIndex);
  void clipRemoved(const QString &clipId, int trackIndex);
  void clipAdded(const QString &clipId, int trackIndex);
  void visualFrameInvalidated();
  void activeSequenceChanged();
  void sequenceListChanged();

private:
  [[nodiscard]] timeline::TimelineSequence *activeSequence() noexcept;
  [[nodiscard]] const timeline::TimelineSequence *
  activeSequence() const noexcept;
  [[nodiscard]] std::vector<TimelineTrack *> rawTracks() const;
  int firstVideoTrackIndex() const;
  int firstAudioTrackIndex() const;
  int findMatchingAudioTrack(int videoTrackIndex) const;

  ProjectManager *m_projectManager{nullptr};
  MediaPool *m_mediaPool{nullptr};
  XylaUndoStack *m_undoStack{nullptr};
  PlaybackManager *m_playbackManager{nullptr};

  std::vector<std::unique_ptr<timeline::TimelineSequence>> m_sequences;
  size_t m_activeSequenceIndex{0};

  std::unique_ptr<anim::AnimationManager> m_animationManager;
  timeline::TimelineInteractionSession m_interactionSession;
  mutable SnapEngine m_snapEngine;
  QString m_lastSelectedClipId;
  TimelineCompositor *m_timelineCompositor{nullptr};
};

} // namespace xyla
