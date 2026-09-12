import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "da1nonlycheezit.steam-launch-options"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var settings: ({})

  property string pluginDir: {
    var u = Qt.resolvedUrl("scripts/steam_lo.py")
    return u
  }
  property string scriptPath: {
    var u = Qt.resolvedUrl("scripts/steam_lo.py")
    if (u.indexOf("file://") === 0)
      return decodeURIComponent(u.substring(7))
    return u
  }

  property var games: []
  property var filteredGames: []
  property string searchText: ""
  property int selectedIndex: -1
  property string selectedAppId: ""
  property string selectedName: ""
  property string selectedIcon: ""
  property string gameOptions: ""
  property string defaultOptions: ""
  property string statusText: ""
  property bool busy: false
  property bool dropdownOpen: false

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() {
    if (root.opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  Process {
    id: listProc
    property var onDone: null
    command: ["python3", root.scriptPath, "list"]
    running: false
    stdout: StdioCollector { }
    stderr: StdioCollector { }
    onExited: function (code) {
      root.busy = false
      var text = stdout.text || ""
      try {
        var data = JSON.parse(text.trim())
        if (data.ok && data.games) {
          root.games = data.games
          root.applyFilter()
          root.statusText = data.games.length + " games"
        } else {
          root.statusText = (data && data.error) ? data.error : "List failed"
        }
      } catch (e) {
        root.statusText = "List parse failed"
      }
    }
  }

  Process {
    id: defaultsGetProc
    command: ["python3", root.scriptPath, "defaults-get"]
    running: false
    stdout: StdioCollector { }
    onExited: function (code) {
      try {
        var data = JSON.parse((stdout.text || "").trim())
        if (data.defaults !== undefined)
          root.defaultOptions = data.defaults
      } catch (e) {}
    }
  }

  Process {
    id: defaultsSetProc
    property string pending: ""
    command: ["python3", root.scriptPath, "defaults-set", pending]
    running: false
    stdout: StdioCollector { }
    onExited: function (code) {
      root.busy = false
      root.statusText = code === 0 ? "Defaults saved" : "Defaults save failed"
    }
  }

  Process {
    id: setProc
    property string appid: ""
    property string opts: ""
    command: ["python3", root.scriptPath, "set", appid, opts]
    running: false
    stdout: StdioCollector { }
    onExited: function (code) {
      root.busy = false
      root.statusText = code === 0 ? "Saved " + appid : "Save failed"
      if (code === 0) refreshList()
    }
  }

  Process {
    id: applyProc
    property string opts: ""
    command: ["python3", root.scriptPath, "apply-defaults", opts]
    running: false
    stdout: StdioCollector { }
    onExited: function (code) {
      root.busy = false
      try {
        var data = JSON.parse((stdout.text || "").trim())
        if (data.ok)
          root.statusText = "Applied defaults to " + (data.count || 0) + " games"
        else
          root.statusText = data.error || "Apply failed"
      } catch (e) {
        root.statusText = "Apply failed"
      }
      refreshList()
    }
  }

  function refreshList() {
    busy = true
    listProc.running = false
    listProc.command = ["python3", scriptPath, "list"]
    listProc.running = true
  }

  function loadDefaults() {
    defaultsGetProc.running = false
    defaultsGetProc.running = true
  }

  function saveDefaults() {
    busy = true
    defaultsSetProc.pending = defaultOptions
    defaultsSetProc.command = ["python3", scriptPath, "defaults-set", defaultOptions]
    defaultsSetProc.running = false
    defaultsSetProc.running = true
  }

  function saveGameOptions() {
    if (!selectedAppId) {
      statusText = "Pick a game"
      return
    }
    busy = true
    setProc.appid = selectedAppId
    setProc.opts = gameOptions
    setProc.command = ["python3", scriptPath, "set", selectedAppId, gameOptions]
    setProc.running = false
    setProc.running = true
  }

  function applyDefaultsToEmpty() {
    busy = true
    applyProc.opts = defaultOptions
    applyProc.command = ["python3", scriptPath, "apply-defaults", defaultOptions]
    applyProc.running = false
    applyProc.running = true
  }

  function applyFilter() {
    var q = (searchText || "").trim().toLowerCase()
    if (!q) {
      filteredGames = games.slice()
    } else {
      var out = []
      for (var i = 0; i < games.length; i++) {
        var g = games[i]
        if ((g.name && g.name.toLowerCase().indexOf(q) >= 0) ||
            (g.appid && String(g.appid).indexOf(q) >= 0))
          out.push(g)
      }
      filteredGames = out
    }
  }

  function selectGame(g) {
    selectedAppId = g.appid
    selectedName = g.name
    selectedIcon = g.icon || ""
    gameOptions = g.launchOptions || ""
    dropdownOpen = false
    statusText = g.name + (g.hasOptions ? " (has options)" : " (empty)")
  }

  onOpenedChanged: {
    if (opened) {
      loadDefaults()
      refreshList()
    }
  }

  onSearchTextChanged: applyFilter()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentCol.implicitHeight + Style.space(16))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: contentCol
        width: parent.width
        spacing: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(12)

        Text {
          width: parent.width
          text: "Steam Launch Options"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          width: parent.width
          text: "Default launch options"
          color: root.barForeground
          font.pixelSize: Style.font.caption
          opacity: 0.8
        }
        Text {
          width: parent.width
          text: "Applied only to newly installed / empty games when you press Apply to empty."
          color: root.barForeground
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          opacity: 0.55
        }

        Rectangle {
          width: parent.width
          height: defaultsField.implicitHeight + Style.space(8)
          radius: 6
          color: Qt.rgba(0, 0, 0, 0.25)
          border.color: Qt.rgba(1, 1, 1, 0.12)
          border.width: 1

          TextInput {
            id: defaultsField
            anchors.fill: parent
            anchors.margins: Style.space(6)
            text: root.defaultOptions
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: TextInput.Wrap
            selectByMouse: true
            onTextChanged: root.defaultOptions = text
            placeholderText: "e.g. gamescope -f -- %command%"
          }
        }

        Row {
          spacing: Style.space(8)
          Button {
            text: "Save defaults"
            enabled: !root.busy
            onClicked: root.saveDefaults()
          }
          Button {
            text: "Apply to empty"
            enabled: !root.busy && root.defaultOptions.length > 0
            onClicked: root.applyDefaultsToEmpty()
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(1, 1, 1, 0.1)
        }

        Text {
          width: parent.width
          text: "Game"
          color: root.barForeground
          font.pixelSize: Style.font.caption
          opacity: 0.8
        }

        Rectangle {
          width: parent.width
          height: searchField.implicitHeight + Style.space(8)
          radius: 6
          color: Qt.rgba(0, 0, 0, 0.25)
          border.color: Qt.rgba(1, 1, 1, 0.12)
          border.width: 1

          TextInput {
            id: searchField
            anchors.fill: parent
            anchors.margins: Style.space(6)
            text: root.searchText
            color: root.barForeground
            font.pixelSize: Style.font.body
            selectByMouse: true
            onTextChanged: root.searchText = text
            onActiveFocusChanged: if (activeFocus) root.dropdownOpen = true
            placeholderText: "Search games…"
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.selectedAppId.length > 0

          Image {
            width: 48
            height: 22
            fillMode: Image.PreserveAspectCrop
            source: root.selectedIcon
            visible: root.selectedIcon.length > 0
          }
          Text {
            text: root.selectedName + "  [" + root.selectedAppId + "]"
            color: root.barForeground
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent.width - 60
          }
        }

        Rectangle {
          width: parent.width
          height: Math.min(180, gameList.contentHeight + 4)
          visible: root.dropdownOpen && root.filteredGames.length > 0
          radius: 6
          color: Qt.rgba(0, 0, 0, 0.45)
          border.color: Qt.rgba(1, 1, 1, 0.12)
          border.width: 1
          clip: true

          ListView {
            id: gameList
            anchors.fill: parent
            anchors.margins: 2
            model: root.filteredGames
            clip: true
            delegate: Item {
              width: gameList.width
              height: 36
              required property var modelData
              required property int index

              Rectangle {
                anchors.fill: parent
                color: ma.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
              }
              Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 6
                spacing: 8
                Image {
                  width: 40
                  height: 18
                  fillMode: Image.PreserveAspectCrop
                  source: modelData.icon || ""
                }
                Text {
                  text: modelData.name
                  color: root.barForeground
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  width: gameList.width - 100
                }
                Text {
                  text: modelData.hasOptions ? "●" : "○"
                  color: modelData.hasOptions ? "#6c6" : "#888"
                  font.pixelSize: Style.font.caption
                }
              }
              MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.selectGame(modelData)
              }
            }
          }
        }

        Button {
          text: root.dropdownOpen ? "Hide list" : "Show list (" + root.filteredGames.length + ")"
          onClicked: root.dropdownOpen = !root.dropdownOpen
        }

        Text {
          width: parent.width
          text: "Launch options for selected game"
          color: root.barForeground
          font.pixelSize: Style.font.caption
          opacity: 0.8
        }

        Rectangle {
          width: parent.width
          height: gameOptsField.implicitHeight + Style.space(8)
          radius: 6
          color: Qt.rgba(0, 0, 0, 0.25)
          border.color: Qt.rgba(1, 1, 1, 0.12)
          border.width: 1

          TextInput {
            id: gameOptsField
            anchors.fill: parent
            anchors.margins: Style.space(6)
            text: root.gameOptions
            color: root.barForeground
            font.pixelSize: Style.font.body
            wrapMode: TextInput.Wrap
            selectByMouse: true
            enabled: root.selectedAppId.length > 0
            onTextChanged: root.gameOptions = text
            placeholderText: selectedAppId ? "Launch options…" : "Select a game first"
          }
        }

        Row {
          spacing: Style.space(8)
          Button {
            text: "Save"
            enabled: !root.busy && root.selectedAppId.length > 0
            onClicked: root.saveGameOptions()
          }
          Button {
            text: "Refresh"
            enabled: !root.busy
            onClicked: root.refreshList()
          }
        }

        Text {
          width: parent.width
          text: root.busy ? "Working…" : root.statusText
          color: root.barForeground
          font.pixelSize: Style.font.caption
          opacity: 0.7
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}