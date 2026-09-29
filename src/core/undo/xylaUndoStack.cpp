#include "xylaUndoStack.hpp"
#include "core/actions/xylaActionManager.hpp"

namespace xyla {

XylaUndoStack::XylaUndoStack(QObject *parent) : QObject(parent), m_stack(this) {
  s_instance = this;
  m_stack.setUndoLimit(100);

  // forward underlying QUndoStack signals to reactive QML properties
  connect(&m_stack, &QUndoStack::canUndoChanged, this,
          &XylaUndoStack::canUndoChanged);
  connect(&m_stack, &QUndoStack::canRedoChanged, this,
          &XylaUndoStack::canRedoChanged);
  connect(&m_stack, &QUndoStack::undoTextChanged, this,
          &XylaUndoStack::undoTextChanged);
  connect(&m_stack, &QUndoStack::redoTextChanged, this,
          &XylaUndoStack::redoTextChanged);
  connect(&m_stack, &QUndoStack::cleanChanged, this,
          &XylaUndoStack::cleanChanged);
  connect(&m_stack, &QUndoStack::indexChanged, this,
          &XylaUndoStack::indexChanged);
}

XylaUndoStack::~XylaUndoStack() {
  if (s_instance == this) {
    s_instance = nullptr;
  }
}

void XylaUndoStack::registerActions(XylaActionManager *actionMgr) {
  if (!actionMgr) {
    return;
  }

  actionMgr->registerAction({"edit.undo",
                             {"Undo", "Undo previous edit action",
                              "Reverts the last timeline modification"},
                             "qrc:/assets/icons/undo.svg",
                             true,
                             [this]() { undo(); }});

  actionMgr->registerAction(
      {"edit.redo",
       {"Redo", "Redo previous edit action",
        "Re-applies the last reverted timeline modification"},
       "qrc:/assets/icons/redo.svg",
       true,
       [this]() { redo(); }});
}

void XylaUndoStack::push(std::unique_ptr<XylaCommand> command) {
  if (!command) {
    return;
  }

  // release ownership directly to QUndoStack
  m_stack.push(command.release());
}

void XylaUndoStack::beginMacro(const QString &text) {
  m_stack.beginMacro(text);
}

void XylaUndoStack::endMacro() { m_stack.endMacro(); }

bool XylaUndoStack::undo() {
  if (!m_stack.canUndo()) {
    return false;
  }

  m_stack.undo();
  return true;
}

bool XylaUndoStack::redo() {
  if (!m_stack.canRedo()) {
    return false;
  }

  m_stack.redo();
  return true;
}

void XylaUndoStack::clear() { m_stack.clear(); }

void XylaUndoStack::setClean() { m_stack.setClean(); }

bool XylaUndoStack::canUndo() const noexcept { return m_stack.canUndo(); }

bool XylaUndoStack::canRedo() const noexcept { return m_stack.canRedo(); }

bool XylaUndoStack::isClean() const noexcept { return m_stack.isClean(); }

QString XylaUndoStack::undoText() const { return m_stack.undoText(); }

QString XylaUndoStack::redoText() const { return m_stack.redoText(); }

void XylaUndoStack::setUndoLimit(int limit) { m_stack.setUndoLimit(limit); }

} // namespace xyla
