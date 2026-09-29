#pragma once

#include "xylaCommand.hpp"

#include <QObject>
#include <QString>
#include <QUndoStack>
#include <memory>

namespace xyla {

class XylaActionManager;

/**
 * @brief Centralized undo and redo manager wrapping Qt's QUndoStack engine.
 *
 * Manages the application undo history, exposes reactive properties to QML,
 * coordinates macro transaction grouping, and monitors document dirty status.
 *
 * @note Implemented as a singleton service accessible via instance().
 */
class XylaUndoStack : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool canUndo READ canUndo NOTIFY canUndoChanged)
  Q_PROPERTY(bool canRedo READ canRedo NOTIFY canRedoChanged)
  Q_PROPERTY(QString undoText READ undoText NOTIFY undoTextChanged)
  Q_PROPERTY(QString redoText READ redoText NOTIFY redoTextChanged)
  Q_PROPERTY(bool isClean READ isClean NOTIFY cleanChanged)

public:
  explicit XylaUndoStack(QObject *parent = nullptr);
  ~XylaUndoStack() override;

  [[nodiscard]] static XylaUndoStack *instance() noexcept { return s_instance; }

  /**
   * @brief Register global undo and redo shortcuts with the action manager.
   *
   * @param actionMgr Application action manager receiving the registrations.
   */
  void registerActions(XylaActionManager *actionMgr);

  /**
   * @brief Push a new command onto the stack and execute its initial redo
   * action.
   *
   * Takes ownership of the command pointer and discards any existing redo
   * history.
   *
   * @param command Command instance to push.
   */
  void push(std::unique_ptr<XylaCommand> command);

  /**
   * @brief Begin a compound macro transaction grouping multiple commands.
   *
   * All subsequent commands pushed until endMacro() collapses into a single
   * undo step.
   *
   * @param text Human-readable description of the compound transaction.
   */
  Q_INVOKABLE void beginMacro(const QString &text);

  /**
   * @brief Terminate the active compound macro transaction.
   */
  Q_INVOKABLE void endMacro();

  Q_INVOKABLE bool undo();
  Q_INVOKABLE bool redo();
  Q_INVOKABLE void clear();
  Q_INVOKABLE void setClean();

  [[nodiscard]] bool canUndo() const noexcept;
  [[nodiscard]] bool canRedo() const noexcept;
  [[nodiscard]] bool isClean() const noexcept;
  [[nodiscard]] QString undoText() const;
  [[nodiscard]] QString redoText() const;

  /**
   * @brief Configure maximum allowed undo history depth.
   *
   * @param limit Maximum number of commands retained before oldest are pruned.
   */
  void setUndoLimit(int limit);

signals:
  void canUndoChanged(bool canUndo);
  void canRedoChanged(bool canRedo);
  void undoTextChanged(const QString &text);
  void redoTextChanged(const QString &text);
  void cleanChanged(bool isClean);
  void indexChanged(int idx);

private:
  inline static XylaUndoStack *s_instance{nullptr};
  QUndoStack m_stack;
};

} // namespace xyla
