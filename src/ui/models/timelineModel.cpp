#include "timelineModel.hpp"
#include "core/audio/timeline/audioTimelineManager.hpp"
#include "core/audio/timeline/waveformGenerator.hpp"
#include "core/log/logger.hpp"
#include "core/timeline/component/audioComponent.hpp"
#include "core/timeline/component/transformComponent.hpp"
#include "ui/models/timeline/TimelineCutEngine.hpp"
#include "ui/models/timeline/TimelinePlacementEngine.hpp"
#include "ui/models/timeline/TimelineRippleEngine.hpp"
#include "ui/models/timeline/TimelineSelectionEngine.hpp"
#include "ui/models/timeline/TimelineThreePointEngine.hpp"
#include "ui/models/timeline/TimelineTrimEngine.hpp"

#include <QFileInfo>
#include <QJsonArray>
#include <QUuid>
#include <algorithm>
#include <cmath>

namespace xyla {

TimelineModel::TimelineModel(ProjectManager *projectManager,
                             MediaPool *mediaPool, XylaUndoStack *undoStack,
                             QObject *parent)
    : QAbstractListModel(parent), m_projectManager(projectManager),
      m_mediaPool(mediaPool), m_undoStack(undoStack) {
  m_animationManager =
      std::make_unique<anim::AnimationManager>(undoStack, this);

  // initialize project with a default sequence
  auto defaultSeq = std::make_unique<timeline::TimelineSequence>(
      QUuid::createUuid().toString(QUuid::WithoutBraces),
      QStringLiteral("Timeline 1"));
  defaultSeq->createDefaultTracks(2, 2);

  m_animationManager->setActiveTable(defaultSeq->animationTable());
  defaultSeq->bindAnimationManager(*m_animationManager);
  m_sequences.push_back(std::move(defaultSeq));
  m_activeSequenceIndex = 0;
}

timeline::TimelineSequence *TimelineModel::activeSequence() noexcept {
  if (m_sequences.empty()) {
    auto fallback = std::make_unique<timeline::TimelineSequence>(
        QUuid::createUuid().toString(QUuid::WithoutBraces),
        QStringLiteral("Timeline 1"));
    fallback->createDefaultTracks(2, 2);
    m_sequences.push_back(std::move(fallback));
    m_activeSequenceIndex = 0;
  }

  if (m_activeSequenceIndex >= m_sequences.size()) {
    m_activeSequenceIndex = 0;
  }

  return m_sequences[m_activeSequenceIndex].get();
}

const timeline::TimelineSequence *
TimelineModel::activeSequence() const noexcept {
  if (m_sequences.empty()) {
    return nullptr;
  }
  const size_t idx =
      (m_activeSequenceIndex < m_sequences.size()) ? m_activeSequenceIndex : 0;
  return m_sequences[idx].get();
}

int TimelineModel::rowCount(const QModelIndex &parent) const {
  if (parent.isValid()) {
    return 0;
  }
  const auto *seq = activeSequence();
  return seq ? static_cast<int>(seq->tracks().size()) : 0;
}

QVariant TimelineModel::data(const QModelIndex &index, int role) const {
  const auto *seq = activeSequence();
  if (!seq || !index.isValid() || index.row() < 0 ||
      static_cast<size_t>(index.row()) >= seq->tracks().size()) {
    return {};
  }

  const auto &track = seq->tracks()[static_cast<size_t>(index.row())];
  if (!track) {
    return {};
  }

  switch (role) {
  case TrackIdRole:
    return track->getTrackId();
  case TrackNameRole:
    return track->getName();
  case TrackKindRole:
    return static_cast<int>(track->getKind());
  case TrackLockedRole:
    return track->getIsLocked();
  case TrackMutedRole:
    return track->getIsMuted();
  case TrackSelectedRole:
    return (index.row() == seq->selectedTrackIndex());
  case TrackHeightRole:
    return seq->trackMetrics().trackHeight(index.row());
  default:
    return {};
  }
}

QHash<int, QByteArray> TimelineModel::roleNames() const {
  QHash<int, QByteArray> roles;
  roles[TrackIdRole] = "trackId";
  roles[TrackNameRole] = "trackName";
  roles[TrackKindRole] = "trackKind";
  roles[TrackLockedRole] = "trackLocked";
  roles[TrackMutedRole] = "trackMuted";
  roles[TrackSelectedRole] = "isTrackSelected";
  roles[TrackHeightRole] = "trackHeight";
  return roles;
}

std::vector<TimelineTrack *> TimelineModel::rawTracks() const {
  const auto *seq = activeSequence();
  if (!seq) {
    return {};
  }
  std::vector<TimelineTrack *> raw;
  raw.reserve(seq->tracks().size());
  for (const auto &t : seq->tracks()) {
    raw.push_back(t.get());
  }
  return raw;
}

// sequence management
QString TimelineModel::activeSequenceId() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->id() : QString{};
}

QString TimelineModel::activeSequenceName() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->name() : QString{};
}

void TimelineModel::setActiveSequenceName(const QString &name) {
  auto *seq = activeSequence();
  if (seq && seq->name() != name) {
    seq->setName(name);
    emit activeSequenceChanged();
    emit sequenceListChanged();
    markDirty();
  }
}

QVariantList TimelineModel::sequenceList() const {
  QVariantList list;
  list.reserve(static_cast<int>(m_sequences.size()));
  for (size_t i = 0; i < m_sequences.size(); ++i) {
    QVariantMap map;
    map[QStringLiteral("id")] = m_sequences[i]->id();
    map[QStringLiteral("name")] = m_sequences[i]->name();
    map[QStringLiteral("index")] = static_cast<int>(i);
    map[QStringLiteral("isActive")] = (i == m_activeSequenceIndex);
    list.append(map);
  }
  return list;
}

QString TimelineModel::createSequence(const QString &name) {
  const QString seqName =
      name.trimmed().isEmpty()
          ? QString("Timeline %1").arg(m_sequences.size() + 1)
          : name.trimmed();

  auto newSeq = std::make_unique<timeline::TimelineSequence>(
      QUuid::createUuid().toString(QUuid::WithoutBraces), seqName);
  newSeq->createDefaultTracks(2, 2);

  if (m_animationManager) {
    newSeq->bindAnimationManager(*m_animationManager);
  }

  const QString newId = newSeq->id();
  m_sequences.push_back(std::move(newSeq));

  emit sequenceListChanged();
  markDirty();

  switchSequence(newId);
  return newId;
}

bool TimelineModel::deleteSequence(const QString &sequenceId) {
  if (m_sequences.size() <= 1) {
    XYLA_LOG_WARN("TimelineModel", "deleteSequence rejected: project must "
                                   "maintain at least one sequence.");
    return false;
  }

  auto it = std::find_if(m_sequences.begin(), m_sequences.end(),
                         [&](const auto &s) { return s->id() == sequenceId; });

  if (it == m_sequences.end()) {
    return false;
  }

  const size_t removedIndex = std::distance(m_sequences.begin(), it);
  const bool wasActive = (removedIndex == m_activeSequenceIndex);

  beginResetModel();
  m_sequences.erase(it);

  if (wasActive) {
    m_activeSequenceIndex = std::min(removedIndex, m_sequences.size() - 1);
    if (m_animationManager) {
      m_animationManager->setActiveTable(activeSequence()->animationTable());
    }
  } else if (removedIndex < m_activeSequenceIndex) {
    m_activeSequenceIndex--;
  }

  endResetModel();

  emit activeSequenceChanged();
  emit sequenceListChanged();
  emit trackCountChanged();
  emit trackMetricsChanged();
  markDirty();
  return true;
}

bool TimelineModel::switchSequence(const QString &sequenceId) {
  for (size_t i = 0; i < m_sequences.size(); ++i) {
    if (m_sequences[i]->id() == sequenceId) {
      return switchSequenceByIndex(static_cast<int>(i));
    }
  }
  return false;
}

bool TimelineModel::switchSequenceByIndex(int index) {
  if (index < 0 || static_cast<size_t>(index) >= m_sequences.size()) {
    return false;
  }

  if (static_cast<size_t>(index) == m_activeSequenceIndex) {
    return true;
  }

  beginResetModel();
  m_activeSequenceIndex = static_cast<size_t>(index);
  auto *seq = activeSequence();

  // swap active animation table handle on the global animation manager
  if (m_animationManager && seq) {
    m_animationManager->setActiveTable(seq->animationTable());
  }

  endResetModel();

  emit activeSequenceChanged();
  emit sequenceListChanged();
  emit trackCountChanged();
  emit trackMetricsChanged();
  emit zoomFactorChanged(getZoomFactor());
  emit horizontalOffsetChanged(getHorizontalOffset());
  emit selectedClipsChanged(getSelectedClipIds());
  emit selectedClipIdChanged(getSelectedClipId());
  emit selectedClipDataChanged();
  return true;
}

// track metrics delegation
int TimelineModel::totalTracksHeight() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->trackMetrics().totalHeight() : 0;
}

int TimelineModel::getTrackHeight(int trackIndex) const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->trackMetrics().trackHeight(trackIndex) : 68;
}

void TimelineModel::setTrackHeight(int trackIndex, int height) {
  auto *seq = activeSequence();
  if (seq && seq->trackMetrics().setTrackHeight(trackIndex, height)) {
    emit trackMetricsChanged();
    emit dataChanged(index(trackIndex, 0), index(trackIndex, 0));
  }
}

int TimelineModel::getTrackY(int trackIndex) const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->trackMetrics().trackY(trackIndex) : 0;
}

int TimelineModel::getTrackAtY(int canvasY) const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->trackMetrics().trackAtY(canvasY) : 0;
}

void TimelineModel::createDefaultTracks(int videoCount, int audioCount) {
  auto *seq = activeSequence();
  if (!seq) {
    return;
  }

  beginResetModel();
  seq->createDefaultTracks(videoCount, audioCount);
  endResetModel();

  emit trackCountChanged();
  emit trackMetricsChanged();
  markDirty();
}

void TimelineModel::addVideoTrack() {
  auto *seq = activeSequence();
  if (!seq) {
    return;
  }

  int videoCount = 0;
  for (const auto &t : seq->tracks()) {
    if (t && t->getKind() == TrackKind::Video) {
      videoCount++;
    }
  }

  auto track = std::make_shared<TimelineTrack>(
      QUuid::createUuid().toString(QUuid::WithoutBraces),
      QString("Video %1").arg(videoCount + 1), TrackKind::Video);

  beginInsertRows(QModelIndex(), 0, 0);
  seq->tracks().insert(seq->tracks().begin(), track);
  seq->trackMetrics().setTrackCount(seq->tracks().size());
  endInsertRows();

  emit trackCountChanged();
  emit trackMetricsChanged();
  markDirty();
}

void TimelineModel::addAudioTrack() {
  auto *seq = activeSequence();
  if (!seq) {
    return;
  }

  int audioCount = 0;
  for (const auto &t : seq->tracks()) {
    if (t && t->getKind() == TrackKind::Audio) {
      audioCount++;
    }
  }

  auto track = std::make_shared<TimelineTrack>(
      QUuid::createUuid().toString(QUuid::WithoutBraces),
      QString("Audio %1").arg(audioCount + 1), TrackKind::Audio);

  int insertIndex = static_cast<int>(seq->tracks().size());
  beginInsertRows(QModelIndex(), insertIndex, insertIndex);
  seq->tracks().push_back(track);
  seq->trackMetrics().setTrackCount(seq->tracks().size());
  endInsertRows();

  emit trackCountChanged();
  emit trackMetricsChanged();
  markDirty();
}

int TimelineModel::getTrackKind(int trackIndex) const {
  auto *t = getTrack(trackIndex);
  return t ? static_cast<int>(t->getKind()) : -1;
}

bool TimelineModel::isTrackLocked(int trackIndex) const {
  auto *t = getTrack(trackIndex);
  return t ? t->getIsLocked() : false;
}

void TimelineModel::setTrackLocked(int trackIndex, bool locked) {
  auto *t = getTrack(trackIndex);
  if (!t) {
    return;
  }
  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::LockTrackCommand>(this, trackIndex, locked));
  } else {
    applyDirectTrackLock(trackIndex, locked);
  }
}

void TimelineModel::toggleTrackLock(int trackIndex) {
  setTrackLocked(trackIndex, !isTrackLocked(trackIndex));
}

bool TimelineModel::isTrackMuted(int trackIndex) const {
  auto *t = getTrack(trackIndex);
  return t ? t->getIsMuted() : false;
}

void TimelineModel::setTrackMuted(int trackIndex, bool muted) {
  auto *t = getTrack(trackIndex);
  if (!t) {
    return;
  }
  if (t->getIsMuted() != muted) {
    t->setIsMuted(muted);
    emit trackDataChanged(trackIndex);
    emit dataChanged(index(trackIndex, 0), index(trackIndex, 0));
    markDirty();
  }
}

void TimelineModel::toggleTrackMute(int trackIndex) {
  setTrackMuted(trackIndex, !isTrackMuted(trackIndex));
}

void TimelineModel::selectTrack(int trackIndex) {
  auto *seq = activeSequence();
  if (!seq || trackIndex < 0 ||
      static_cast<size_t>(trackIndex) >= seq->tracks().size()) {
    return;
  }
  if (seq->selectedTrackIndex() == trackIndex) {
    return;
  }

  const int prevIndex = seq->selectedTrackIndex();
  seq->setSelectedTrackIndex(trackIndex);

  if (prevIndex >= 0 && static_cast<size_t>(prevIndex) < seq->tracks().size()) {
    emit dataChanged(index(prevIndex, 0), index(prevIndex, 0));
  }
  emit dataChanged(index(trackIndex, 0), index(trackIndex, 0));
  emit selectedTrackIndexChanged(trackIndex);
}

// spatial collision resolution
QJsonObject TimelineModel::resolvePlacement(
    const QStringList &clipIds, int64_t desiredStartFrame, int targetTrackIndex,
    int64_t originFrame, int originTrack, int64_t lastValidFrame,
    int lastValidTrack) const {
  std::vector<timeline::PlacementClip> movingClips;
  movingClips.reserve(clipIds.size());

  for (const auto &id : clipIds) {
    if (const auto *c = findClip(id)) {
      movingClips.push_back({c->getClipId(), c->getTiming().trackIndex,
                             c->getTiming().startFrame,
                             c->getTiming().durationFrames,
                             getTrackKind(c->getTiming().trackIndex)});
    }
  }

  const auto anchorId = clipIds.isEmpty() ? QString{} : clipIds.first();
  const auto result = timeline::TimelinePlacementEngine::resolvePlacement(
      rawTracks(), movingClips, anchorId, desiredStartFrame, targetTrackIndex,
      originFrame, originTrack, lastValidFrame, lastValidTrack);

  QJsonObject obj;
  obj["valid"] = result.valid;
  obj["frame"] = static_cast<double>(result.frame);
  obj["track"] = result.trackIndex;
  return obj;
}

QVariantMap TimelineModel::querySnap(int64_t candidateStart, int64_t duration,
                                     int targetTrack, int64_t playheadFrame,
                                     double zoomFactor,
                                     const QStringList &ignoreClipIds,
                                     double snapPixelThreshold) const {
  if (zoomFactor <= 0.0) {
    return SnapResult1D{}.toVariantMap();
  }

  m_snapEngine.clearAll();
  m_snapEngine.addPoint(0.0, 0.0, "timeline_origin", 100);
  if (playheadFrame >= 0) {
    m_snapEngine.addPoint(static_cast<double>(playheadFrame), 0.0, "playhead",
                          50);
  }

  const auto *seq = activeSequence();
  if (!seq) {
    return SnapResult1D{}.toVariantMap();
  }

  for (size_t t = 0; t < seq->tracks().size(); ++t) {
    const auto *track = seq->tracks()[t].get();
    if (!track || track->getIsLocked()) {
      continue;
    }

    for (const auto &c : track->getClips()) {
      if (ignoreClipIds.contains(c.getClipId())) {
        continue;
      }

      m_snapEngine.addPoint(c.getTiming().startFrame, 0.0, "clip_edge", 10);
      m_snapEngine.addPoint(c.getTiming().endFrame(), 0.0, "clip_edge", 10);

      if (static_cast<int>(t) == targetTrack) {
        m_snapEngine.addIntervalX(c.getTiming().startFrame,
                                  c.getTiming().endFrame(), "track_gap");
      }
    }
  }

  const double worldThreshold = snapPixelThreshold / zoomFactor;
  return m_snapEngine
      .snap1D(static_cast<double>(candidateStart),
              static_cast<double>(duration), worldThreshold)
      .toVariantMap();
}

// clip lifecycle
QString TimelineModel::addClip(const QString &assetId, const QString &name,
                               int trackIndex, int64_t startFrame,
                               int64_t durationFrames, int64_t sourceInFrame) {
  if (assetId.trimmed().isEmpty() || durationFrames <= 0) {
    return QString{};
  }

  auto *targetTrk = getTrack(trackIndex);
  if (!targetTrk || targetTrk->getIsLocked()) {
    return QString{};
  }

  bool hasVideo = false;
  bool hasAudio = false;

  if (m_mediaPool) {
    auto asset = m_mediaPool->getAsset(assetId);
    if (asset) {
      hasVideo = !asset->metadata().videoStreams.empty();
      hasAudio = !asset->metadata().audioStreams.empty();
    }
  }

  std::vector<timeline::AddClipPayload> clipsToAdd;
  const QString primaryId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  QString sharedGroupId;

  if (!hasVideo && hasAudio) {
    int aTrack = (targetTrk->getKind() == TrackKind::Audio)
                     ? trackIndex
                     : firstAudioTrackIndex();
    if (aTrack == -1)
      return QString{};

    TimelineClipCreateInfo info{
        primaryId,
        assetId,
        name,
        {startFrame, durationFrames, sourceInFrame, aTrack, 1.0}};
    TimelineClip audioClip(info);
    audioClip.addComponent(std::make_unique<AudioComponent>());
    clipsToAdd.push_back({std::move(audioClip), aTrack});
  } else {
    int vTrack = (targetTrk->getKind() == TrackKind::Video)
                     ? trackIndex
                     : firstVideoTrackIndex();
    if (vTrack == -1)
      return QString{};

    if (hasAudio) {
      sharedGroupId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    }

    TimelineClipCreateInfo vInfo{
        primaryId,
        assetId,
        name,
        {startFrame, durationFrames, sourceInFrame, vTrack, 1.0}};
    TimelineClip videoClip(vInfo);
    videoClip.addComponent(std::make_unique<TransformComponent>());
    clipsToAdd.push_back({std::move(videoClip), vTrack});

    if (hasAudio) {
      int aTrack = findMatchingAudioTrack(vTrack);
      if (auto *aTrk = getTrack(aTrack)) {
        if (aTrk->getKind() == TrackKind::Audio) {
          const QString aId =
              QUuid::createUuid().toString(QUuid::WithoutBraces);
          TimelineClipCreateInfo aInfo{
              aId,
              assetId,
              name,
              {startFrame, durationFrames, sourceInFrame, aTrack, 1.0}};
          TimelineClip aClip(aInfo);
          aClip.addComponent(std::make_unique<AudioComponent>());
          clipsToAdd.push_back({std::move(aClip), aTrack});
        }
      }
    }
  }

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::AddClipsCommand>(
        this, std::move(clipsToAdd), sharedGroupId));
  } else {
    QStringList ids;
    for (const auto &item : clipsToAdd) {
      applyDirectAdd(item.clip, item.trackIndex);
      ids.append(item.clip.getClipId());
    }
    if (ids.size() > 1 && !sharedGroupId.isEmpty()) {
      applyDirectLink(ids, sharedGroupId);
    }
    applyDirectSelection(ids);
  }

  return primaryId;
}

QString TimelineModel::addTitleClip(int trackIndex, int64_t startFrame,
                                    int64_t durationFrames,
                                    const QString &text) {
  if (durationFrames <= 0)
    return QString{};
  auto *target = getTrack(trackIndex);
  if (!target || target->getIsLocked())
    return QString{};

  int vTrack = (target->getKind() == TrackKind::Video) ? trackIndex
                                                       : firstVideoTrackIndex();
  if (vTrack == -1)
    return QString{};

  const QString clipId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  const QString clipName =
      text.trimmed().isEmpty() ? QStringLiteral("Title") : text;

  TimelineClipCreateInfo info{clipId,
                              QString("asset_title_%1").arg(clipId),
                              clipName,
                              {startFrame, durationFrames, 0, vTrack, 1.0}};

  TimelineClip titleClip = TimelineClip::createTitleClip(info, clipName);
  if (m_animationManager) {
    titleClip.bindAnimationManager(*m_animationManager);
  }

  std::vector<timeline::AddClipPayload> clipsToAdd;
  clipsToAdd.push_back({std::move(titleClip), vTrack});

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::AddClipsCommand>(
        this, std::move(clipsToAdd)));
  } else {
    applyDirectAdd(clipsToAdd[0].clip, vTrack);
    applyDirectSelection({clipId});
  }

  return clipId;
}

QString TimelineModel::addSvgClip(const QString &filePath, int trackIndex,
                                  int64_t startFrame, int64_t durationFrames) {
  if (filePath.trimmed().isEmpty() || durationFrames <= 0)
    return QString{};
  QFileInfo fi(filePath);
  if (!fi.exists())
    return QString{};

  auto *target = getTrack(trackIndex);
  if (!target || target->getIsLocked())
    return QString{};

  int vTrack = (target->getKind() == TrackKind::Video) ? trackIndex
                                                       : firstVideoTrackIndex();
  if (vTrack == -1)
    return QString{};

  const QString clipId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  TimelineClipCreateInfo info{clipId,
                              filePath,
                              fi.fileName(),
                              {startFrame, durationFrames, 0, vTrack, 1.0}};

  TimelineClip svgClip = TimelineClip::createSvgClip(info, filePath);
  if (m_animationManager) {
    svgClip.bindAnimationManager(*m_animationManager);
  }

  std::vector<timeline::AddClipPayload> clipsToAdd;
  clipsToAdd.push_back({std::move(svgClip), vTrack});

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::AddClipsCommand>(
        this, std::move(clipsToAdd)));
  } else {
    applyDirectAdd(clipsToAdd[0].clip, vTrack);
    applyDirectSelection({clipId});
  }

  return clipId;
}

bool TimelineModel::removeClip(const QString &clipId, int trackIndex) {
  if (clipId.isEmpty())
    return false;
  auto *seq = activeSequence();
  if (!seq)
    return false;

  std::vector<timeline::DeletedClipPayload> toDelete;

  if (trackIndex >= 0 &&
      static_cast<size_t>(trackIndex) < seq->tracks().size()) {
    if (const auto *c = seq->tracks()[trackIndex]->findClip(clipId)) {
      toDelete.push_back({*c, trackIndex});
    }
  } else {
    for (size_t t = 0; t < seq->tracks().size(); ++t) {
      if (const auto *c = seq->tracks()[t]->findClip(clipId)) {
        toDelete.push_back({*c, static_cast<int>(t)});
        break;
      }
    }
  }

  if (toDelete.empty())
    return false;

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::DeleteClipsCommand>(
        this, std::move(toDelete)));
  } else {
    applyDirectRemove(toDelete[0].clip.getClipId(), toDelete[0].trackIndex);
  }
  return true;
}

// cutting operations
bool TimelineModel::razorCut(int64_t cutFrame, int targetTrack) {
  auto *seq = activeSequence();
  if (!seq)
    return false;

  auto plan = timeline::TimelineCutEngine::planRazorCut(
      rawTracks(), seq->selectedClipIds(), seq->linkGraph(), cutFrame,
      targetTrack);

  if (plan.isEmpty())
    return false;

  std::vector<timeline::CutInfo> cuts;
  cuts.reserve(plan.cuts.size());
  for (const auto &c : plan.cuts) {
    cuts.push_back({c.sourceClipId, c.trackIndex, c.cutFrame, c.newRightClipId,
                    c.newRightGroupId});
  }

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::MultiCutCommand>(this, std::move(cuts)));
  } else {
    for (const auto &c : cuts) {
      applyDirectCut(c.id, c.track, c.frame, c.rightId, c.rightGroupId);
    }
    applyDirectSelection(plan.newSelectionIds);
  }
  return true;
}

bool TimelineModel::cutClip(const QString &clipId, int64_t frame) {
  auto *seq = activeSequence();
  if (!seq)
    return false;

  auto plan = timeline::TimelineCutEngine::planClipCut(rawTracks(), clipId,
                                                       seq->linkGraph(), frame);
  if (plan.isEmpty())
    return false;

  std::vector<timeline::CutInfo> cuts;
  cuts.reserve(plan.cuts.size());
  for (const auto &c : plan.cuts) {
    cuts.push_back({c.sourceClipId, c.trackIndex, c.cutFrame, c.newRightClipId,
                    c.newRightGroupId});
  }

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::MultiCutCommand>(this, std::move(cuts)));
  } else {
    for (const auto &c : cuts) {
      applyDirectCut(c.id, c.track, c.frame, c.rightId, c.rightGroupId);
    }
    applyDirectSelection(plan.newSelectionIds);
  }
  return true;
}

bool TimelineModel::cutAtPlayhead(int64_t playheadFrame) {
  return razorCut(playheadFrame, -1);
}

// movement and transforms
bool TimelineModel::moveClip(const QString &clipId, int fromTrack, int toTrack,
                             int64_t newStartFrame) {
  auto *clip = findClip(clipId);
  if (!clip)
    return false;
  const int64_t deltaFrames = newStartFrame - clip->getTiming().startFrame;
  const int deltaTracks = toTrack - fromTrack;
  return moveClips(QStringList{clipId}, deltaFrames, deltaTracks);
}

bool TimelineModel::moveClips(const QStringList &clipIds, int64_t deltaFrames,
                              int deltaTracks) {
  if (clipIds.isEmpty() || (deltaFrames == 0 && deltaTracks == 0))
    return false;

  std::vector<timeline::MoveRecord> moves;
  moves.reserve(clipIds.size());

  for (const auto &id : clipIds) {
    if (const auto *c = findClip(id)) {
      const int srcT = c->getTiming().trackIndex;
      const int dstT = std::max(0, srcT + deltaTracks);
      const int64_t oldS = c->getTiming().startFrame;
      const int64_t newS = std::max<int64_t>(0, oldS + deltaFrames);
      moves.push_back({id, srcT, dstT, oldS, newS});
    }
  }

  if (moves.empty())
    return false;

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::MoveClipsCommand>(this, std::move(moves)));
  } else {
    for (const auto &m : moves) {
      applyDirectMove(m.clipId, m.srcTrack, m.dstTrack, m.newStartFrame);
    }
  }
  return true;
}

bool TimelineModel::rippleMoveClip(const QString &clipId, int toTrack,
                                   int64_t dropFrame, bool global) {
  auto *clip = findClip(clipId);
  if (!clip || !getTrack(toTrack))
    return false;

  const int srcTrack = clip->getTiming().trackIndex;
  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::RippleMoveCommand>(
        this, clipId, srcTrack, toTrack, dropFrame, global));
  } else {
    int64_t origStart = 0;
    QString splitRightId;
    applyDirectRippleMove(clipId, srcTrack, toTrack, dropFrame, global,
                          origStart, splitRightId);
  }
  return true;
}

bool TimelineModel::rollEdit(const QString &leftClipId,
                             const QString &rightClipId, int64_t splitFrame) {
  const auto *left = findClip(leftClipId);
  const auto *right = findClip(rightClipId);
  if (!left || !right)
    return false;

  const int64_t leftDur = getAssetDuration(left->getAssetId());
  const int64_t rightDur = getAssetDuration(right->getAssetId());

  const auto limits = timeline::TimelineTrimEngine::calculateRollLimits(
      *left, *right, leftDur, rightDur);
  const int64_t delta = splitFrame - left->getTiming().endFrame();
  const auto roll =
      timeline::TimelineTrimEngine::computeRoll(*left, *right, delta, limits);

  timeline::RollParticipant lPart{left->getClipId(),
                                  left->getTiming().trackIndex,
                                  left->getTiming().startFrame,
                                  left->getTiming().durationFrames,
                                  left->getTiming().sourceInFrame,
                                  roll.leftStartFrame,
                                  roll.leftDurationFrames,
                                  roll.leftSourceInFrame};

  timeline::RollParticipant rPart{right->getClipId(),
                                  right->getTiming().trackIndex,
                                  right->getTiming().startFrame,
                                  right->getTiming().durationFrames,
                                  right->getTiming().sourceInFrame,
                                  roll.rightStartFrame,
                                  roll.rightDurationFrames,
                                  roll.rightSourceInFrame};

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::RollEditCommand>(this, lPart, rPart));
  } else {
    applyDirectTrim(lPart.clipId, lPart.trackIndex, lPart.newStartFrame,
                    lPart.newDurationFrames, lPart.newSourceInFrame, false,
                    false);
    applyDirectTrim(rPart.clipId, rPart.trackIndex, rPart.newStartFrame,
                    rPart.newDurationFrames, rPart.newSourceInFrame, false,
                    false);
  }
  return true;
}

bool TimelineModel::slipClip(const QString &clipId, int64_t newSourceInFrame) {
  auto *clip = findClip(clipId);
  if (!clip)
    return false;

  const QStringList linked = getLinkedClipIds(clipId);
  std::vector<timeline::SlipEntry> entries;
  const int64_t deltaIn = newSourceInFrame - clip->getTiming().sourceInFrame;

  for (const auto &id : linked) {
    if (const auto *c = findClip(id)) {
      const int64_t assetDur = getAssetDuration(c->getAssetId());
      const int64_t clampedIn = timeline::TimelineTrimEngine::computeSlip(
          c->getTiming().sourceInFrame, -deltaIn, c->getTiming().durationFrames,
          assetDur);
      entries.push_back({id, c->getTiming().trackIndex,
                         c->getTiming().sourceInFrame, clampedIn});
    }
  }

  if (entries.empty())
    return false;

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::BatchSlipCommand>(this, std::move(entries)));
  } else {
    for (const auto &e : entries) {
      if (auto *trk = getTrack(e.trackIndex)) {
        if (auto *c = trk->findClip(e.clipId)) {
          auto timing = c->getTiming();
          timing.sourceInFrame = e.newSourceInFrame;
          c->setTiming(timing);
          notifyTimelineChanged(e.trackIndex);
        }
      }
    }
  }
  return true;
}

bool TimelineModel::trimClip(const QString &clipId, int trackIndex,
                             int64_t newStart, int64_t newDur, int64_t newIn,
                             bool isRipple) {
  auto *primary = findClip(clipId);
  if (!primary)
    return false;

  const int64_t deltaStart = newStart - primary->getTiming().startFrame;
  const int64_t deltaDur = newDur - primary->getTiming().durationFrames;
  const int64_t deltaIn = newIn - primary->getTiming().sourceInFrame;

  if (deltaStart == 0 && deltaDur == 0 && deltaIn == 0)
    return false;

  const QStringList linked = getLinkedClipIds(clipId);
  std::vector<timeline::BatchTrimEntry> entries;
  entries.reserve(linked.size());

  for (const auto &id : linked) {
    if (const auto *c = findClip(id)) {
      entries.push_back(
          {id, c->getTiming().trackIndex, c->getTiming().startFrame,
           c->getTiming().durationFrames, c->getTiming().sourceInFrame,
           std::max<int64_t>(0, c->getTiming().startFrame + deltaStart),
           std::max<int64_t>(1, c->getTiming().durationFrames + deltaDur),
           std::max<int64_t>(0, c->getTiming().sourceInFrame + deltaIn),
           isRipple, getGlobalRippleMode()});
    }
  }

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::BatchTrimCommand>(this, std::move(entries)));
  } else {
    for (const auto &e : entries) {
      applyDirectTrim(e.clipId, e.trackIndex, e.newStartFrame,
                      e.newDurationFrames, e.newSourceInFrame, e.isRipple,
                      e.isGlobal);
    }
  }
  return true;
}

bool TimelineModel::rippleTrimToPlayhead(int64_t playheadFrame, bool trimIn) {
  auto *seq = activeSequence();
  if (!seq)
    return false;

  std::vector<timeline::BatchTrimEntry> entries;
  for (const auto &id : seq->selectedClipIds()) {
    if (const auto *c = findClip(id)) {
      if (c->getTiming().containsFrame(playheadFrame)) {
        int64_t nStart = c->getTiming().startFrame;
        int64_t nDur = c->getTiming().durationFrames;
        int64_t nIn = c->getTiming().sourceInFrame;

        if (trimIn && playheadFrame > nStart) {
          const int64_t delta = playheadFrame - nStart;
          nStart = playheadFrame;
          nDur = std::max<int64_t>(1, nDur - delta);
          nIn += delta;
        } else if (!trimIn && playheadFrame > nStart &&
                   playheadFrame <= nStart + nDur) {
          nDur = std::max<int64_t>(1, playheadFrame - nStart);
        }

        entries.push_back(
            {id, c->getTiming().trackIndex, c->getTiming().startFrame,
             c->getTiming().durationFrames, c->getTiming().sourceInFrame,
             nStart, nDur, nIn, true, seq->globalRippleMode()});
      }
    }
  }

  if (entries.empty())
    return false;

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::BatchTrimCommand>(this, std::move(entries)));
  } else {
    for (const auto &e : entries) {
      applyDirectTrim(e.clipId, e.trackIndex, e.newStartFrame,
                      e.newDurationFrames, e.newSourceInFrame, e.isRipple,
                      e.isGlobal);
    }
  }
  return true;
}

// 3-point editing
bool TimelineModel::insertClip(const QString &assetId, int64_t sourceIn,
                               int64_t sourceOut, int64_t playheadFrame,
                               int targetTrack) {
  if (assetId.isEmpty() || !m_mediaPool)
    return false;
  auto *seq = activeSequence();
  if (!seq)
    return false;

  int tTrack = targetTrack >= 0 ? targetTrack : firstVideoTrackIndex();
  if (tTrack < 0)
    return false;

  int64_t dur = std::max<int64_t>(1, sourceOut - sourceIn + 1);
  QString assetName = "Clip";
  bool hasVideo = false;
  bool hasAudio = false;

  if (auto asset = m_mediaPool->getAsset(assetId)) {
    assetName = asset->name();
    hasVideo = !asset->metadata().videoStreams.empty();
    hasAudio = !asset->metadata().audioStreams.empty();
  }

  std::vector<timeline::TargetTrackAssignment> targets;
  if (!hasVideo && hasAudio) {
    targets.push_back({tTrack, true});
  } else {
    targets.push_back({tTrack, false});
    if (hasAudio) {
      int aTrack = findMatchingAudioTrack(tTrack);
      if (aTrack >= 0)
        targets.push_back({aTrack, true});
    }
  }

  auto plan = timeline::TimelineThreePointEngine::planInsert(
      rawTracks(), targets, assetId, assetName, sourceIn, dur, playheadFrame,
      seq->globalRippleMode());

  if (!plan.isValid())
    return false;

  std::vector<timeline::ThreePointTrackDelta> deltas;
  for (auto &d : plan.deltas) {
    timeline::ThreePointTrackDelta td;
    td.trackIndex = d.trackIndex;
    td.addedClips = std::move(d.addedClips);
    td.removedClips = std::move(d.removedClips);
    for (const auto &m : d.modifiedClips) {
      td.modifiedClips.push_back(
          {m.clipId, m.trackIndex, m.oldTiming, m.newTiming});
    }
    deltas.push_back(std::move(td));
  }

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::ThreePointEditCommand>(
        this, std::move(deltas), "Insert Clip"));
  } else {
    // apply direct insert
  }
  return true;
}

bool TimelineModel::overwriteClip(const QString &assetId, int64_t sourceIn,
                                  int64_t sourceOut, int64_t playheadFrame,
                                  int targetTrack) {
  if (assetId.isEmpty() || !m_mediaPool)
    return false;
  auto *seq = activeSequence();
  if (!seq)
    return false;

  int tTrack = targetTrack >= 0 ? targetTrack : firstVideoTrackIndex();
  if (tTrack < 0)
    return false;

  int64_t dur = std::max<int64_t>(1, sourceOut - sourceIn + 1);
  QString assetName = "Clip";
  bool hasVideo = false;
  bool hasAudio = false;

  if (auto asset = m_mediaPool->getAsset(assetId)) {
    assetName = asset->name();
    hasVideo = !asset->metadata().videoStreams.empty();
    hasAudio = !asset->metadata().audioStreams.empty();
  }

  std::vector<timeline::TargetTrackAssignment> targets;
  if (!hasVideo && hasAudio) {
    targets.push_back({tTrack, true});
  } else {
    targets.push_back({tTrack, false});
    if (hasAudio) {
      int aTrack = findMatchingAudioTrack(tTrack);
      if (aTrack >= 0)
        targets.push_back({aTrack, true});
    }
  }

  auto plan = timeline::TimelineThreePointEngine::planOverwrite(
      rawTracks(), targets, assetId, assetName, sourceIn, dur, playheadFrame);

  if (!plan.isValid())
    return false;

  std::vector<timeline::ThreePointTrackDelta> deltas;
  for (auto &d : plan.deltas) {
    timeline::ThreePointTrackDelta td;
    td.trackIndex = d.trackIndex;
    td.addedClips = std::move(d.addedClips);
    td.removedClips = std::move(d.removedClips);
    for (const auto &m : d.modifiedClips) {
      td.modifiedClips.push_back(
          {m.clipId, m.trackIndex, m.oldTiming, m.newTiming});
    }
    deltas.push_back(std::move(td));
  }

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::ThreePointEditCommand>(
        this, std::move(deltas), "Overwrite Clip"));
  } else {
    // apply direct overwrite
  }
  return true;
}

// selection
void TimelineModel::selectClip(const QString &clipId, bool toggle,
                               bool isRange) {
  auto *seq = activeSequence();
  if (!seq)
    return;

  if (isRange && !m_lastSelectedClipId.isEmpty()) {
    const auto newSel =
        timeline::TimelineSelectionEngine::resolveRangeSelection(
            rawTracks(), m_lastSelectedClipId, clipId, seq->linkGraph());
    applyDirectSelection(newSel);
  } else if (toggle) {
    const auto newSel =
        timeline::TimelineSelectionEngine::resolveToggleSelection(
            seq->selectedClipIds(), clipId, seq->linkGraph());
    m_lastSelectedClipId = clipId;
    applyDirectSelection(newSel);
  } else {
    const auto newSel = seq->linkGraph().getLinkedClipIds(clipId);
    m_lastSelectedClipId = clipId;
    applyDirectSelection(newSel);
  }
}

void TimelineModel::selectBox(int64_t startFrame, int64_t endFrame,
                              int startTrack, int endTrack, bool toggle) {
  auto *seq = activeSequence();
  if (!seq)
    return;

  const auto newSel = timeline::TimelineSelectionEngine::resolveBoxSelection(
      rawTracks(), startFrame, endFrame, startTrack, endTrack, seq->linkGraph(),
      seq->selectedClipIds(), toggle);
  applyDirectSelection(newSel);
}

void TimelineModel::selectAll() {
  QStringList all;
  for (const auto *t : rawTracks()) {
    if (!t)
      continue;
    for (const auto &c : t->getClips())
      all.append(c.getClipId());
  }
  applyDirectSelection(all);
}

void TimelineModel::clearSelection() { applyDirectSelection({}); }

void TimelineModel::deleteSelectedClips(bool ripple) {
  auto *seq = activeSequence();
  if (!seq || seq->selectedClipIds().isEmpty())
    return;

  std::vector<timeline::DeletedClipPayload> toDelete;
  for (const auto &id : seq->selectedClipIds()) {
    if (const auto *c = findClip(id)) {
      toDelete.push_back({*c, c->getTiming().trackIndex});
    }
  }

  clearSelection();

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::DeleteClipsCommand>(
        this, std::move(toDelete)));
  } else {
    for (const auto &item : toDelete) {
      applyDirectRemove(item.clip.getClipId(), item.trackIndex);
    }
  }
}

bool TimelineModel::canLinkSelection() const {
  const auto *seq = activeSequence();
  return seq && timeline::TimelineSelectionEngine::canLinkSelection(
                    seq->selectedClipIds(), seq->linkGraph());
}

bool TimelineModel::canUnlinkSelection() const {
  const auto *seq = activeSequence();
  return seq && timeline::TimelineSelectionEngine::canUnlinkSelection(
                    seq->selectedClipIds(), seq->linkGraph());
}

void TimelineModel::linkSelectedClips() {
  auto *seq = activeSequence();
  if (!seq || seq->selectedClipIds().size() < 2)
    return;

  std::vector<std::pair<QString, QString>> prev;
  for (const auto &id : seq->selectedClipIds()) {
    if (findClip(id))
      prev.emplace_back(id, seq->linkGraph().getGroupId(id));
  }

  const QString newGroupId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::LinkClipsCommand>(
        this, seq->selectedClipIds(), newGroupId, std::move(prev)));
  } else {
    applyDirectLink(seq->selectedClipIds(), newGroupId);
  }
}

void TimelineModel::unlinkSelectedClips() {
  auto *seq = activeSequence();
  if (!seq || seq->selectedClipIds().isEmpty())
    return;

  QStringList toUnlink;
  std::vector<std::pair<QString, QString>> prev;

  for (const auto &id : seq->selectedClipIds()) {
    const QStringList linked = seq->linkGraph().getLinkedClipIds(id);
    for (const auto &lid : linked) {
      if (!toUnlink.contains(lid)) {
        toUnlink.append(lid);
        if (findClip(lid))
          prev.emplace_back(lid, seq->linkGraph().getGroupId(lid));
      }
    }
  }

  if (toUnlink.isEmpty())
    return;

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<timeline::UnlinkClipsCommand>(
        this, toUnlink, std::move(prev)));
  } else {
    applyDirectLink(toUnlink, QString{});
  }
}

bool TimelineModel::isClipLocked(const QString &clipId) const {
  const auto *c = findClip(clipId);
  return c ? (c->getIsLocked() || isTrackLocked(c->getTiming().trackIndex))
           : false;
}

void TimelineModel::setClipLocked(const QString &clipId, bool locked) {
  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<timeline::LockClipCommand>(this, clipId, locked));
  } else {
    applyDirectClipLock(clipId, locked);
  }
}

void TimelineModel::toggleClipLock(const QString &clipId) {
  setClipLocked(clipId, !isClipLocked(clipId));
}

// interaction sessions
void TimelineModel::beginInteraction(const QString &leaderClipId, int mode,
                                     int64_t maxLimit) {
  std::vector<timeline::ParticipantClip> parts;
  const QStringList targets = getLinkedClipIds(leaderClipId);

  for (const auto &id : targets) {
    if (const auto *c = findClip(id)) {
      parts.push_back({id, c->getTiming().trackIndex, c->getTiming().startFrame,
                       c->getTiming().durationFrames,
                       c->getTiming().sourceInFrame, c->getTiming().trackIndex,
                       c->getTiming().startFrame, c->getTiming().durationFrames,
                       c->getTiming().sourceInFrame});
    }
  }

  if (mode == 0)
    m_interactionSession.beginMove(leaderClipId, parts, false);
  else if (mode == 1)
    m_interactionSession.beginTrim(leaderClipId, parts, true, false);
  else if (mode == 2)
    m_interactionSession.beginTrim(leaderClipId, parts, false, false);
  else if (mode == 3)
    m_interactionSession.beginSlip(parts, maxLimit);
}

void TimelineModel::updateInteraction(int64_t deltaFrames, int deltaTracks) {
  m_interactionSession.updateDelta(deltaFrames, deltaTracks);
  emit visualFrameInvalidated();
}

void TimelineModel::endInteraction(bool commit) {
  Q_UNUSED(commit);
  m_interactionSession.endSession();
  emit visualFrameInvalidated();
}

double TimelineModel::getProjectedStart(const QString &clipId) const {
  if (auto p = m_interactionSession.getParticipant(clipId))
    return static_cast<double>(p->projectedStartFrame);
  if (const auto *c = findClip(clipId))
    return static_cast<double>(c->getTiming().startFrame);
  return 0.0;
}

double TimelineModel::getProjectedDuration(const QString &clipId) const {
  if (auto p = m_interactionSession.getParticipant(clipId))
    return static_cast<double>(p->projectedDurationFrames);
  if (const auto *c = findClip(clipId))
    return static_cast<double>(c->getTiming().durationFrames);
  return 0.0;
}

double TimelineModel::getProjectedSourceIn(const QString &clipId) const {
  if (auto p = m_interactionSession.getParticipant(clipId))
    return static_cast<double>(p->projectedSourceInFrame);
  if (const auto *c = findClip(clipId))
    return static_cast<double>(c->getTiming().sourceInFrame);
  return 0.0;
}

int TimelineModel::getProjectedTrack(const QString &clipId) const {
  if (auto p = m_interactionSession.getParticipant(clipId))
    return p->projectedTrackIndex;
  if (const auto *c = findClip(clipId))
    return c->getTiming().trackIndex;
  return 0;
}

// lookups
std::vector<TimelineClip *>
TimelineModel::getSelectedClips(const ClipTypeFilter &filter) const {
  if (!filter.isValid())
    return {};
  const auto *seq = activeSequence();
  if (!seq)
    return {};

  std::vector<TimelineClip *> res;
  for (const auto &id : seq->selectedClipIds()) {
    auto *c = const_cast<TimelineModel *>(this)->findClip(id);
    if (c && filter.matches(c->getClipType()))
      res.push_back(c);
  }
  return res;
}

TimelineClip *TimelineModel::findClip(const QString &clipId) {
  if (clipId.isEmpty())
    return nullptr;
  auto *seq = activeSequence();
  if (!seq)
    return nullptr;

  for (auto &t : seq->tracks()) {
    if (t) {
      if (auto *c = t->findClip(clipId))
        return c;
    }
  }
  return nullptr;
}

const TimelineClip *TimelineModel::findClip(const QString &clipId) const {
  return const_cast<TimelineModel *>(this)->findClip(clipId);
}

TimelineTrack *TimelineModel::getTrack(int index) const noexcept {
  const auto *seq = activeSequence();
  if (!seq || index < 0 || static_cast<size_t>(index) >= seq->tracks().size())
    return nullptr;
  return seq->tracks()[static_cast<size_t>(index)].get();
}

QString TimelineModel::getAdjacentClipId(const QString &clipId,
                                         bool searchLeft) const {
  const auto *origin = findClip(clipId);
  if (!origin)
    return QString{};
  const auto *t = getTrack(origin->getTiming().trackIndex);
  if (!t)
    return QString{};
  const auto *adj =
      timeline::TimelineTrimEngine::findAdjacentClip(*t, clipId, searchLeft);
  return adj ? adj->getClipId() : QString{};
}

QStringList TimelineModel::getLinkedClipIds(const QString &clipId) const {
  const auto *seq = activeSequence();
  return seq ? seq->linkGraph().getLinkedClipIds(clipId) : QStringList{};
}

QVariantList TimelineModel::getAllClips() const {
  QVariantList list;
  const auto *seq = activeSequence();
  if (!seq)
    return list;

  for (size_t t = 0; t < seq->tracks().size(); ++t) {
    const auto *track = seq->tracks()[t].get();
    if (!track)
      continue;

    for (const auto &c : track->getClips()) {
      QVariantMap m;
      m[QStringLiteral("clipId")] = c.getClipId();
      m[QStringLiteral("name")] = c.getName();
      m[QStringLiteral("assetId")] = c.getAssetId();
      m[QStringLiteral("trackIndex")] = static_cast<int>(t);
      m[QStringLiteral("startFrame")] =
          static_cast<double>(c.getTiming().startFrame);
      m[QStringLiteral("durationFrames")] =
          static_cast<double>(c.getTiming().durationFrames);
      m[QStringLiteral("sourceInFrame")] =
          static_cast<double>(c.getTiming().sourceInFrame);

      // export both semantic flags and string identifier for QML bindings
      const bool isAudio = (c.getClipType() == ClipType::Audio) ||
                           (track->getKind() == TrackKind::Audio);
      const bool isText = (c.getClipType() == ClipType::Text);
      const bool isSvg = (c.getClipType() == ClipType::Svg);

      m[QStringLiteral("isAudio")] = isAudio;
      m[QStringLiteral("isText")] = isText;
      m[QStringLiteral("isSvg")] = isSvg;
      m[QStringLiteral("clipType")] =
          isAudio ? QStringLiteral("Audio")
                  : (isText ? QStringLiteral("Text")
                            : (isSvg ? QStringLiteral("Svg")
                                     : QStringLiteral("Video")));
      m[QStringLiteral("isLocked")] = c.getIsLocked();
      m[QStringLiteral("isMuted")] = c.getIsMuted();
      list.append(m);
    }
  }
  return list;
}

QVariantList TimelineModel::getClipsForTrack(int trackIndex) const {
  QVariantList list;
  const auto *t = getTrack(trackIndex);
  if (!t)
    return list;

  for (const auto &c : t->getClips()) {
    QVariantMap m;
    m[QStringLiteral("clipId")] = c.getClipId();
    m[QStringLiteral("name")] = c.getName();
    m[QStringLiteral("assetId")] = c.getAssetId();
    m[QStringLiteral("trackIndex")] = trackIndex;
    m[QStringLiteral("startFrame")] =
        static_cast<double>(c.getTiming().startFrame);
    m[QStringLiteral("durationFrames")] =
        static_cast<double>(c.getTiming().durationFrames);
    m[QStringLiteral("sourceInFrame")] =
        static_cast<double>(c.getTiming().sourceInFrame);
    m[QStringLiteral("clipType")] = static_cast<int>(c.getClipType());
    list.append(m);
  }
  return list;
}

QVariantMap TimelineModel::getSelectedClipData() const {
  const auto *seq = activeSequence();
  if (!seq || seq->selectedClipId().isEmpty())
    return {};

  const auto *clip = findClip(seq->selectedClipId());
  if (!clip)
    return {};

  QVariantMap data;
  data[QStringLiteral("clipId")] = clip->getClipId();
  data[QStringLiteral("name")] = clip->getName();
  data[QStringLiteral("assetId")] = clip->getAssetId();
  data[QStringLiteral("trackIndex")] = clip->getTiming().trackIndex;
  data[QStringLiteral("startFrame")] =
      static_cast<double>(clip->getTiming().startFrame);
  data[QStringLiteral("durationFrames")] =
      static_cast<double>(clip->getTiming().durationFrames);
  data[QStringLiteral("sourceInFrame")] =
      static_cast<double>(clip->getTiming().sourceInFrame);
  return data;
}

int64_t TimelineModel::getAssetDuration(const QString &assetId) const {
  if (assetId.startsWith("asset_title_") || assetId.startsWith("asset_svg_")) {
    return 86400 * 60;
  }
  if (!m_mediaPool)
    return 0;
  auto asset = m_mediaPool->getAsset(assetId);
  return asset ? asset->metadata().durationFrames(30.0) : 0;
}

QVariantList TimelineModel::getClipWaveformPeaks(const QString &assetId,
                                                 int64_t startFrame,
                                                 int64_t durationFrames,
                                                 int targetPixels) const {
  QVariantList peaksList;
  if (assetId.isEmpty()) {
    XYLA_LOG_WARN("Waveform", "getClipWaveformPeaks called with EMPTY assetId");
    return peaksList;
  }
  if (durationFrames <= 0 || targetPixels <= 0) {
    XYLA_LOG_WARN(
        "Waveform",
        std::format("getClipWaveformPeaks invalid dimensions: dur={}, px={}",
                    durationFrames, targetPixels));
    return peaksList;
  }

  const std::string assetKey = assetId.toStdString();
  auto buffer = audio::AudioTimelineManager::instance().getClipBuffer(assetKey);
  if (!buffer) {
    XYLA_LOG_WARN(
        "Waveform",
        std::format("AudioTimelineManager has NO buffer for assetKey='{}'",
                    assetKey));
    return peaksList;
  }

  auto pyramid =
      audio::WaveformGenerator::instance().getOrGenerate(assetKey, buffer);
  if (!pyramid || !pyramid->isGenerated()) {
    XYLA_LOG_WARN(
        "Waveform",
        std::format("Pyramid failed to generate for assetKey='{}'", assetKey));
    return peaksList;
  }

  double fps = 30.0;
  if (m_projectManager && m_projectManager->hasActiveProject()) {
    if (const auto *proj = m_projectManager->activeProject()) {
      if (proj->fps() > 0.0)
        fps = proj->fps();
    }
  }

  const double sampleRate = 48000.0;
  const int64_t startSample = static_cast<int64_t>(
      (static_cast<double>(startFrame) / fps) * sampleRate);
  const size_t sampleCount = static_cast<size_t>(
      std::max(0.0, (static_cast<double>(durationFrames) / fps) * sampleRate));
  if (sampleCount == 0) {
    XYLA_LOG_WARN("Waveform",
                  std::format("sampleCount is 0 for assetKey='{}'", assetKey));
    return peaksList;
  }

  const size_t pixels = static_cast<size_t>(std::clamp(targetPixels, 1, 8192));
  auto peaks = pyramid->getPeaks(0, startSample, sampleCount, pixels);

  peaksList.reserve(static_cast<int>(peaks.size()));
  for (const auto &p : peaks) {
    QVariantMap map;
    map.insert(QStringLiteral("min"), p.min);
    map.insert(QStringLiteral("max"), p.max);
    peaksList.append(std::move(map));
  }
  return peaksList;
}

qint64 TimelineModel::getDurationFrames() const {
  const auto *seq = activeSequence();
  if (!seq)
    return 0;

  int64_t maxF = 0;
  for (const auto &t : seq->tracks()) {
    if (!t)
      continue;
    for (const auto &c : t->getClips()) {
      maxF = std::max(maxF, static_cast<int64_t>(c.getTiming().endFrame()));
    }
  }
  return maxF;
}

std::shared_ptr<anim::AnimationPropertyTable>
TimelineModel::animationTable() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->animationTable() : nullptr;
}

// direct targets
void TimelineModel::applyDirectAdd(TimelineClip clip, int trackIndex) {
  if (auto *t = getTrack(trackIndex)) {
    const QString cid = clip.getClipId();
    t->insertClip(std::move(clip));
    if (m_animationManager) {
      if (auto *inserted = t->findClip(cid)) {
        inserted->bindAnimationManager(*m_animationManager);
      }
    }
    notifyTimelineChanged(trackIndex);
  }
}

void TimelineModel::applyDirectRemove(const QString &clipId, int trackIndex) {
  auto *seq = activeSequence();
  if (!seq)
    return;
  seq->linkGraph().unregisterClip(clipId);
  if (auto *t = getTrack(trackIndex)) {
    t->removeClip(clipId);
    emit clipRemoved(clipId, trackIndex);
    notifyTimelineChanged(trackIndex);
  }
}

void TimelineModel::applyDirectMove(const QString &clipId, int srcTrack,
                                    int dstTrack, int64_t newStart) {
  auto *src = getTrack(srcTrack);
  auto *dst = getTrack(dstTrack);
  if (!src || !dst)
    return;
  if (srcTrack == dstTrack)
    src->moveClip(clipId, newStart);
  else
    src->transferClipTo(clipId, *dst, newStart, dstTrack);
  notifyTimelineChanged(srcTrack, dstTrack);
}

void TimelineModel::applyDirectTrim(const QString &clipId, int trackIndex,
                                    int64_t start, int64_t dur, int64_t in,
                                    bool isRipple, bool global, bool isUndo) {
  Q_UNUSED(isUndo);
  auto *t = getTrack(trackIndex);
  if (!t)
    return;
  auto *c = t->findClip(clipId);
  if (!c)
    return;

  const int64_t deltaFrames = dur - c->getTiming().durationFrames;
  const int64_t currentEnd = c->getTiming().endFrame();

  if (isRipple && deltaFrames > 0) {
    if (global)
      shiftAllTracksAfter(currentEnd, deltaFrames, clipId);
    else
      t->shiftClipsAfter(currentEnd, deltaFrames, clipId);
  }

  t->trimClip(clipId, start, dur, in);

  if (isRipple && deltaFrames < 0) {
    if (global)
      shiftAllTracksAfter(currentEnd, deltaFrames, clipId);
    else
      t->shiftClipsAfter(currentEnd, deltaFrames, clipId);
  }

  notifyTimelineChanged(trackIndex);
}

void TimelineModel::applyDirectCut(const QString &clipId, int trackIndex,
                                   int64_t cutFrame, const QString &newRightId,
                                   const QString &newRightGroupId) {
  auto *t = getTrack(trackIndex);
  auto *seq = activeSequence();
  if (!t || !seq)
    return;
  if (t->splitClip(clipId, cutFrame, newRightId)) {
    if (!newRightGroupId.isEmpty()) {
      seq->linkGraph().registerClip(newRightId, newRightGroupId);
    }
    notifyTimelineChanged(trackIndex);
  }
}

void TimelineModel::applyDirectUncut(const QString &leftClipId, int trackIndex,
                                     const QString &rightClipId) {
  auto *t = getTrack(trackIndex);
  auto *seq = activeSequence();
  if (!t || !seq)
    return;
  if (t->uncutClips(leftClipId, rightClipId)) {
    seq->linkGraph().unregisterClip(rightClipId);
    notifyTimelineChanged(trackIndex);
  }
}

void TimelineModel::applyDirectSelection(const QStringList &selection) {
  auto *seq = activeSequence();
  if (!seq)
    return;
  seq->setSelectedClipIds(selection);
  seq->setSelectedClipId(
      timeline::TimelineSelectionEngine::resolvePrimaryClipId(rawTracks(),
                                                              selection));

  emit selectedClipsChanged(seq->selectedClipIds());
  emit selectedClipIdChanged(seq->selectedClipId());
  emit selectedClipDataChanged();
}

void TimelineModel::applyDirectClipLock(const QString &clipId, bool locked) {
  const QStringList linked = getLinkedClipIds(clipId);
  for (const auto &id : linked) {
    if (auto *c = findClip(id)) {
      c->setIsLocked(locked);
      emit clipPropertiesChanged(id);
      emit trackDataChanged(c->getTiming().trackIndex);
    }
  }
  emit selectedClipDataChanged();
  markDirty();
}

void TimelineModel::applyDirectTrackLock(int trackIndex, bool locked) {
  if (auto *t = getTrack(trackIndex)) {
    t->setIsLocked(locked);
    emit trackDataChanged(trackIndex);
    emit dataChanged(index(trackIndex, 0), index(trackIndex, 0));
    markDirty();
  }
}

void TimelineModel::applyDirectLink(const QStringList &clipIds,
                                    const QString &groupId) {
  auto *seq = activeSequence();
  if (!seq)
    return;
  if (groupId.isEmpty())
    seq->linkGraph().unlink(clipIds);
  else
    seq->linkGraph().link(clipIds, groupId);

  for (const auto &id : clipIds) {
    if (const auto *c = findClip(id)) {
      emit clipPropertiesChanged(id);
      emit trackDataChanged(c->getTiming().trackIndex);
    }
  }
  emit selectedClipDataChanged();
}

void TimelineModel::applyDirectRestoreLinkGroups(
    const std::vector<std::pair<QString, QString>> &groups) {
  auto *seq = activeSequence();
  if (!seq)
    return;
  seq->linkGraph().restoreLinkGroups(groups);
  for (const auto &[id, g] : groups) {
    if (const auto *c = findClip(id)) {
      emit clipPropertiesChanged(id);
      emit trackDataChanged(c->getTiming().trackIndex);
    }
  }
  emit selectedClipDataChanged();
}

void TimelineModel::applyDirectRippleMove(const QString &clipId, int srcTrack,
                                          int dstTrack, int64_t dropFrame,
                                          bool global,
                                          int64_t &outOriginalStart,
                                          QString &outSplitRightId) {
  outSplitRightId.clear();
  auto *src = getTrack(srcTrack);
  auto *dst = getTrack(dstTrack);
  if (!src || !dst)
    return;
  auto *c = src->findClip(clipId);
  if (!c)
    return;

  outOriginalStart = c->getTiming().startFrame;
  const int64_t dur = c->getTiming().durationFrames;
  TimelineClip moving = *c;

  src->removeClip(clipId);
  if (global)
    shiftAllTracksAfter(outOriginalStart, -dur, clipId);
  else
    src->shiftClipsAfter(outOriginalStart, -dur, clipId);

  const int64_t ins = dst->resolveInsertFrame(dropFrame, dur);
  if (global)
    shiftAllTracksAfter(ins, dur, clipId);
  else
    dst->shiftClipsAfter(ins, dur, clipId);

  ClipTiming t = moving.getTiming();
  t.startFrame = ins;
  t.trackIndex = dstTrack;
  moving.setTiming(t);
  dst->insertClip(std::move(moving));

  notifyTimelineChanged(srcTrack, dstTrack);
}

void TimelineModel::applyDirectUndoRippleMove(const QString &clipId,
                                              int srcTrack, int dstTrack,
                                              int64_t dropFrame, bool global,
                                              int64_t originalStart,
                                              const QString &splitRightId) {
  Q_UNUSED(dropFrame);
  Q_UNUSED(splitRightId);
  auto *src = getTrack(srcTrack);
  auto *dst = getTrack(dstTrack);
  if (!src || !dst)
    return;
  auto *c = dst->findClip(clipId);
  if (!c)
    return;

  const int64_t dur = c->getTiming().durationFrames;
  const int64_t curS = c->getTiming().startFrame;
  TimelineClip moving = *c;

  dst->removeClip(clipId);
  if (global) {
    shiftAllTracksAfter(curS, -dur, clipId);
    shiftAllTracksAfter(originalStart, dur, clipId);
  } else {
    dst->shiftClipsAfter(curS, -dur, clipId);
    src->shiftClipsAfter(originalStart, dur, clipId);
  }

  ClipTiming t = moving.getTiming();
  t.startFrame = originalStart;
  t.trackIndex = srcTrack;
  moving.setTiming(t);
  src->insertClip(std::move(moving));

  notifyTimelineChanged(srcTrack, dstTrack);
}

void TimelineModel::notifyTimelineChanged(int trackA, int trackB) {
  if (trackA >= 0 && static_cast<size_t>(trackA) < trackCount()) {
    emit trackDataChanged(trackA);
    emit dataChanged(index(trackA, 0), index(trackA, 0));
  }
  if (trackB >= 0 && trackB != trackA &&
      static_cast<size_t>(trackB) < trackCount()) {
    emit trackDataChanged(trackB);
    emit dataChanged(index(trackB, 0), index(trackB, 0));
  }
  emit selectedClipDataChanged();
  markDirty();
}

void TimelineModel::markDirty() {
  if (m_projectManager) {
    m_projectManager->setHasUnsavedChanges(true);
  }
  emit visualFrameInvalidated();
}

void TimelineModel::shiftAllTracksAfter(int64_t fromFrame, int64_t deltaFrames,
                                        const QString &ignoreClipId) {
  auto *seq = activeSequence();
  if (!seq)
    return;
  for (auto &t : seq->tracks()) {
    if (t && !t->getIsLocked()) {
      t->shiftClipsAfter(fromFrame, deltaFrames, ignoreClipId);
    }
  }
}

size_t TimelineModel::trackCount() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->tracks().size() : 0;
}

double TimelineModel::getZoomFactor() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->zoomFactor() : 1.0;
}

void TimelineModel::setZoomFactor(double factor) {
  auto *seq = activeSequence();
  if (seq) {
    factor = std::clamp(factor, 0.1, 10.0);
    if (std::abs(seq->zoomFactor() - factor) > 0.0001) {
      seq->setZoomFactor(factor);
      emit zoomFactorChanged(factor);
    }
  }
}

double TimelineModel::getHorizontalOffset() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->horizontalOffset() : 0.0;
}

void TimelineModel::setHorizontalOffset(double offset) {
  auto *seq = activeSequence();
  if (seq) {
    offset = std::max(0.0, offset);
    if (std::abs(seq->horizontalOffset() - offset) > 0.0001) {
      seq->setHorizontalOffset(offset);
      emit horizontalOffsetChanged(offset);
    }
  }
}

bool TimelineModel::getSnappingEnabled() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->snappingEnabled() : true;
}

void TimelineModel::setSnappingEnabled(bool enabled) {
  auto *seq = activeSequence();
  if (seq && seq->snappingEnabled() != enabled) {
    seq->setSnappingEnabled(enabled);
    emit snappingEnabledChanged(enabled);
  }
}

bool TimelineModel::getGlobalRippleMode() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->globalRippleMode() : false;
}

void TimelineModel::setGlobalRippleMode(bool enabled) {
  auto *seq = activeSequence();
  if (seq && seq->globalRippleMode() != enabled) {
    seq->setGlobalRippleMode(enabled);
    emit globalRippleModeChanged(enabled);
  }
}

QString TimelineModel::getSelectedClipId() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->selectedClipId() : QString{};
}

void TimelineModel::setSelectedClipId(const QString &clipId) {
  selectClip(clipId, false, false);
}

QStringList TimelineModel::getSelectedClipIds() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->selectedClipIds() : QStringList{};
}

int TimelineModel::getSelectedTrackIndex() const noexcept {
  const auto *seq = activeSequence();
  return seq ? seq->selectedTrackIndex() : -1;
}

void TimelineModel::setSelectedTrackIndex(int trackIndex) {
  selectTrack(trackIndex);
}

int TimelineModel::firstVideoTrackIndex() const {
  const auto *seq = activeSequence();
  if (!seq)
    return -1;
  for (size_t i = 0; i < seq->tracks().size(); ++i) {
    if (seq->tracks()[i] && seq->tracks()[i]->getKind() == TrackKind::Video) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

int TimelineModel::firstAudioTrackIndex() const {
  const auto *seq = activeSequence();
  if (!seq)
    return -1;
  for (size_t i = 0; i < seq->tracks().size(); ++i) {
    if (seq->tracks()[i] && seq->tracks()[i]->getKind() == TrackKind::Audio) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

int TimelineModel::findMatchingAudioTrack(int videoTrackIndex) const {
  const auto *seq = activeSequence();
  if (!seq)
    return -1;

  std::vector<int> videoTracks;
  std::vector<int> audioTracks;

  for (size_t i = 0; i < seq->tracks().size(); ++i) {
    if (seq->tracks()[i]) {
      if (seq->tracks()[i]->getKind() == TrackKind::Video)
        videoTracks.push_back(static_cast<int>(i));
      else if (seq->tracks()[i]->getKind() == TrackKind::Audio)
        audioTracks.push_back(static_cast<int>(i));
    }
  }

  if (audioTracks.empty())
    return -1;
  auto it = std::find(videoTracks.begin(), videoTracks.end(), videoTrackIndex);
  const size_t vRank =
      (it != videoTracks.end()) ? std::distance(videoTracks.begin(), it) : 0;
  const size_t dist = (videoTracks.size() - 1) - vRank;
  const size_t targetAudioRank = std::min(dist, audioTracks.size() - 1);
  return audioTracks[targetAudioRank];
}

// serialization across all sequences
QJsonObject TimelineModel::serialize() const {
  QJsonObject obj;
  QJsonArray seqArray;

  for (const auto &seq : m_sequences) {
    if (seq) {
      seqArray.append(seq->serialize());
    }
  }

  obj[QStringLiteral("sequences")] = seqArray;
  obj[QStringLiteral("activeSequenceId")] = activeSequenceId();
  return obj;
}

void TimelineModel::deserialize(const QJsonObject &obj) {
  beginResetModel();
  m_sequences.clear();

  const QJsonArray seqArray = obj.value(QStringLiteral("sequences")).toArray();
  for (const auto &v : seqArray) {
    if (v.isObject()) {
      if (auto seq = timeline::TimelineSequence::deserialize(
              v.toObject(), m_animationManager.get())) {
        m_sequences.push_back(std::move(seq));
      }
    }
  }

  if (m_sequences.empty()) {
    auto defSeq = std::make_unique<timeline::TimelineSequence>(
        QUuid::createUuid().toString(QUuid::WithoutBraces),
        QStringLiteral("Timeline 1"));
    defSeq->createDefaultTracks(2, 2);
    m_sequences.push_back(std::move(defSeq));
  }

  const QString activeId =
      obj.value(QStringLiteral("activeSequenceId")).toString();
  m_activeSequenceIndex = 0;

  for (size_t i = 0; i < m_sequences.size(); ++i) {
    if (m_sequences[i]->id() == activeId) {
      m_activeSequenceIndex = i;
      break;
    }
  }

  if (m_animationManager) {
    m_animationManager->setActiveTable(activeSequence()->animationTable());
  }

  endResetModel();

  emit activeSequenceChanged();
  emit sequenceListChanged();
  emit trackCountChanged();
  emit trackMetricsChanged();
  emit zoomFactorChanged(getZoomFactor());
  emit horizontalOffsetChanged(getHorizontalOffset());
  emit selectedClipsChanged(getSelectedClipIds());
  emit selectedClipIdChanged(getSelectedClipId());
}

void TimelineModel::registerActions(XylaActionManager *actionMgr,
                                    PlaybackManager *playbackMgr) {
  if (!actionMgr)
    return;

  actionMgr->registerAction(
      {"timeline.zoomIn",
       {"Zoom In Timeline", "Magnify timeline horizontal view",
        "Expands timeline scale"},
       "qrc:/assets/icons/zoom-in.svg",
       true,
       [this]() { setZoomFactor(getZoomFactor() * 1.35); }});

  actionMgr->registerAction(
      {"timeline.zoomOut",
       {"Zoom Out Timeline", "Reduce timeline horizontal view",
        "Compresses timeline scale"},
       "qrc:/assets/icons/zoom-out.svg",
       true,
       [this]() { setZoomFactor(getZoomFactor() * 0.74); }});

  actionMgr->registerAction({"timeline.splitClip",
                             {"Split Clip", "Razor clip at playhead",
                              "Splits clip at current playhead frame"},
                             "qrc:/assets/icons/cut.svg",
                             true,
                             [this, playbackMgr]() {
                               if (playbackMgr)
                                 cutAtPlayhead(playbackMgr->currentFrame());
                             }});

  actionMgr->registerAction(
      {"timeline.delete",
       {"Delete", "Delete selected clips", "Lifts selected clips"},
       "qrc:/assets/icons/trash.svg",
       true,
       [this]() { deleteSelectedClips(false); }});
}

void TimelineModel::addTrack(std::shared_ptr<TimelineTrack> track) {
  if (!track) {
    return;
  }
  auto *seq = activeSequence();
  if (!seq) {
    return;
  }

  const int insertIndex = static_cast<int>(seq->tracks().size());
  beginInsertRows(QModelIndex(), insertIndex, insertIndex);
  seq->tracks().push_back(std::move(track));
  seq->trackMetrics().setTrackCount(seq->tracks().size());
  endInsertRows();

  emit trackCountChanged();
  emit trackMetricsChanged();
  markDirty();
}

void TimelineModel::clearTimeline() {
  auto *seq = activeSequence();
  if (!seq) {
    return;
  }

  beginResetModel();
  seq->tracks().clear();
  seq->linkGraph().clear();
  seq->setSelectedClipIds({});
  seq->setSelectedClipId({});
  seq->trackMetrics().setTrackCount(0);
  endResetModel();

  emit trackCountChanged();
  emit trackMetricsChanged();
  emit selectedClipsChanged({});
  emit selectedClipIdChanged({});
  markDirty();
}
} // namespace xyla
