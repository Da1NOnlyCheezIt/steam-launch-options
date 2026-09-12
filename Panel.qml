import QtQuick
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

  // Absolute path — Qt.resolvedUrl is empty when Panel is loaded via Loader
  property string scriptPath: {
    var home = ""
    try { home = Quickshell.env("HOME") || "" } catch (e) { home = "" }
    if (!home)
      home = "/home/worcrest"
    return home + "/.config/omarchy/plugins/da1nonlycheezit.steam-launch-options/scripts/steam_lo.py"
  }

  property var games: []
  property var filteredGames: []
  property string searchText: ""
  property string selectedAppId: ""
  property string selectedName: ""
  property string selectedIcon: ""
  property string gameOptions: ""
  property string defaultOptions: ""
  property string statusText: "Open to load games"
  property bool busy: false
  property bool dropdownOpen: true

  readonly property color fg: (root.bar && root.bar.foreground) ? root.bar.foreground : "#e8e8e8"
  readonly property string fontFamily: (root.bar && root.bar.fontFamily) ? root.bar.fontFamily : Style.font.family

  function open() {
    if (root.controller)
      root.controller.show()
  }
  function close() {
    if (root.controller)
      root.controller.hide()
  }
  function toggle() {
    if (root.opened)
      close()
    else
      open()
  }
  function closeForPopoutSwitch() {
    close()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function makeBtn(parentObj, label, primary, enabledExpr, clickFn) {
    // not used — buttons are inline Rectangles
  }

  Process {
    id: listProc
    command: ["python3", root.scriptPath, "list"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        var out = (text || "").trim()
        if (!out) {
          root.statusText = "List empty stdout path=" + root.scriptPath
          return
        }
        var start = out.indexOf("{")
        var end = out.lastIndexOf("}")
        if (start >= 0 && end > start)
          out = out.substring(start, end + 1)
        try {
          var data = JSON.parse(out)
          if (data.ok && data.games) {
            root.games = data.games
            root.applyFilter()
            root.statusText = data.games.length + " games"
          } else {
            root.statusText = (data && data.error) ? data.error : "List failed"
          }
        } catch (e) {
          root.statusText = "List parse failed: " + out.substring(0, 120)
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim().length)
          console.warn("steam-lo list stderr:", text.trim().substring(0, 200))
      }
    }
    onExited: function (code) {
      if (code !== 0 && root.statusText.indexOf("games") < 0)
        root.statusText = "List exit code " + code + " path=" + root.scriptPath
    }
  }

  Process {
    id: defaultsGetProc
    command: ["python3", root.scriptPath, "defaults-get"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse((text || "").trim())
          if (data.defaults !== undefined)
            root.defaultOptions = data.defaults
        } catch (e) {}
      }
    }
  }

  Process {
    id: defaultsSetProc
    command: ["python3", root.scriptPath, "defaults-set", ""]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        try {
          var data = JSON.parse((text || "").trim())
          root.statusText = data.ok ? "Defaults saved" : "Defaults save failed"
        } catch (e) {
          root.statusText = "Defaults save failed"
        }
      }
    }
    onExited: function (code) {
      if (code !== 0) {
        root.busy = false
        root.statusText = "Defaults save failed"
      }
    }
  }

  Process {
    id: setProc
    command: ["python3", root.scriptPath, "set", "", ""]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        try {
          var data = JSON.parse((text || "").trim())
          root.statusText = data.ok ? ("Saved " + root.selectedAppId) : "Save failed"
          if (data.ok) root.refreshList()
        } catch (e) {
          root.statusText = "Save failed"
        }
      }
    }
    onExited: function (code) {
      if (code !== 0) {
        root.busy = false
        root.statusText = "Save failed"
      }
    }
  }

  Process {
    id: applyProc
    command: ["python3", root.scriptPath, "apply-defaults", ""]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        try {
          var data = JSON.parse((text || "").trim())
          if (data.ok)
            root.statusText = "Applied defaults to " + (data.count || 0) + " games"
          else
            root.statusText = data.error || "Apply failed"
        } catch (e) {
          root.statusText = "Apply failed"
        }
        root.refreshList()
      }
    }
    onExited: function (code) {
      if (code !== 0) {
        root.busy = false
        root.statusText = "Apply failed"
      }
    }
  }

  function refreshList() {
    busy = true
    statusText = "Loading games…"
    listProc.running = false
    listProc.command = ["python3", scriptPath, "list"]
    listProc.running = true
  }

  function loadDefaults() {
    defaultsGetProc.running = false
    defaultsGetProc.command = ["python3", scriptPath, "defaults-get"]
    defaultsGetProc.running = true
  }

  function saveDefaults() {
    busy = true
    defaultsSetProc.running = false
    defaultsSetProc.command = ["python3", scriptPath, "defaults-set", defaultOptions]
    defaultsSetProc.running = true
  }

  function saveGameOptions() {
    if (!selectedAppId) {
      statusText = "Pick a game"
      return
    }
    busy = true
    setProc.running = false
    setProc.command = ["python3", scriptPath, "set", selectedAppId, gameOptions]
    setProc.running = true
  }

  function applyDefaultsToEmpty() {
    busy = true
    applyProc.running = false
    applyProc.command = ["python3", scriptPath, "apply-defaults", defaultOptions]
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
    selectedAppId = String(g.appid)
    selectedName = g.name || selectedAppId
    selectedIcon = g.icon || ""
    gameOptions = g.launchOptions || ""
    statusText = selectedName + (g.hasOptions ? " (has options)" : " (empty)")
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: Math.max(360, panel.fittedContentHeight(contentCol.implicitHeight + 24))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 12
        contentWidth: width
        contentHeight: contentCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentCol
          width: flick.width
          spacing: 10

          Text {
            width: parent.width
            text: "Steam Launch Options"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            width: parent.width
            text: "Default launch options"
            color: root.fg
            font.pixelSize: Style.font.caption
            opacity: 0.8
          }
          Text {
            width: parent.width
            text: "Only applied to empty / newly installed games via Apply to empty."
            color: root.fg
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            opacity: 0.55
          }

          Rectangle {
            width: parent.width
            height: Math.max(36, defaultsField.implicitHeight + 12)
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.25)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1

            TextInput {
              id: defaultsField
              anchors.fill: parent
              anchors.margins: 6
              text: root.defaultOptions
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: TextInput.Wrap
              selectByMouse: true
              onTextChanged: root.defaultOptions = text
            }
          }

          Row {
            spacing: 8

            // Save defaults
            Rectangle {
              width: saveDefLab.implicitWidth + 16
              height: 28
              radius: 6
              color: Qt.rgba(1, 1, 1, root.busy ? 0.05 : 0.12)
              border.color: Qt.rgba(1, 1, 1, 0.14)
              border.width: 1
              opacity: root.busy ? 0.45 : 1
              Text {
                id: saveDefLab
                anchors.centerIn: parent
                text: "Save defaults"
                color: root.fg
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                enabled: !root.busy
                onClicked: root.saveDefaults()
              }
            }

            // Apply to empty
            Rectangle {
              width: applyLab.implicitWidth + 16
              height: 28
              radius: 6
              color: Qt.rgba(0.35, 0.55, 0.95, (!root.busy && root.defaultOptions.length > 0) ? 0.55 : 0.25)
              border.color: Qt.rgba(1, 1, 1, 0.14)
              border.width: 1
              opacity: (!root.busy && root.defaultOptions.length > 0) ? 1 : 0.45
              Text {
                id: applyLab
                anchors.centerIn: parent
                text: "Apply to empty"
                color: root.fg
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                enabled: !root.busy && root.defaultOptions.length > 0
                onClicked: root.applyDefaultsToEmpty()
              }
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
            color: root.fg
            font.pixelSize: Style.font.caption
            opacity: 0.8
          }

          Rectangle {
            width: parent.width
            height: Math.max(32, searchField.implicitHeight + 12)
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.25)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1

            TextInput {
              id: searchField
              anchors.fill: parent
              anchors.margins: 6
              text: root.searchText
              color: root.fg
              font.pixelSize: Style.font.body
              selectByMouse: true
              onTextChanged: root.searchText = text
              onActiveFocusChanged: if (activeFocus) root.dropdownOpen = true
            }
          }

          Row {
            width: parent.width
            spacing: 8
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
              color: root.fg
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              width: parent.width - 60
            }
          }

          Rectangle {
            width: parent.width
            height: root.dropdownOpen ? Math.min(200, Math.max(40, gameList.contentHeight + 4)) : 0
            visible: root.dropdownOpen
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
              boundsBehavior: Flickable.StopAtBounds

              delegate: Item {
                width: gameList.width
                height: 36
                property var game: modelData

                Rectangle {
                  anchors.fill: parent
                  color: rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                  radius: 4
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
                    source: (game && game.icon) ? game.icon : ""
                  }
                  Text {
                    text: (game && game.name) ? game.name : ((game && game.appid) ? game.appid : "")
                    color: root.fg
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    width: gameList.width - 100
                  }
                  Text {
                    text: (game && game.hasOptions) ? "●" : "○"
                    color: (game && game.hasOptions) ? "#6c6" : "#888"
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea {
                  id: rowMa
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: if (game) root.selectGame(game)
                }
              }

              Text {
                anchors.centerIn: parent
                visible: root.filteredGames.length === 0
                text: root.busy ? "Loading…" : "No games"
                color: root.fg
                opacity: 0.5
                font.pixelSize: Style.font.caption
              }
            }
          }

          Rectangle {
            width: toggleLab.implicitWidth + 16
            height: 28
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.12)
            border.color: Qt.rgba(1, 1, 1, 0.14)
            border.width: 1
            Text {
              id: toggleLab
              anchors.centerIn: parent
              text: root.dropdownOpen
                    ? ("Hide list (" + root.filteredGames.length + ")")
                    : ("Show list (" + root.filteredGames.length + ")")
              color: root.fg
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.dropdownOpen = !root.dropdownOpen
            }
          }

          Text {
            width: parent.width
            text: "Launch options for selected game"
            color: root.fg
            font.pixelSize: Style.font.caption
            opacity: 0.8
          }

          Rectangle {
            width: parent.width
            height: Math.max(36, gameOptsField.implicitHeight + 12)
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.25)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
            opacity: root.selectedAppId.length > 0 ? 1 : 0.5

            TextInput {
              id: gameOptsField
              anchors.fill: parent
              anchors.margins: 6
              text: root.gameOptions
              color: root.fg
              font.pixelSize: Style.font.body
              wrapMode: TextInput.Wrap
              selectByMouse: true
              enabled: root.selectedAppId.length > 0
              onTextChanged: root.gameOptions = text
            }
          }

          Row {
            spacing: 8

            Rectangle {
              width: saveLab.implicitWidth + 16
              height: 28
              radius: 6
              color: Qt.rgba(0.35, 0.55, 0.95, (!root.busy && root.selectedAppId.length > 0) ? 0.55 : 0.25)
              border.color: Qt.rgba(1, 1, 1, 0.14)
              border.width: 1
              opacity: (!root.busy && root.selectedAppId.length > 0) ? 1 : 0.45
              Text {
                id: saveLab
                anchors.centerIn: parent
                text: "Save"
                color: root.fg
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                enabled: !root.busy && root.selectedAppId.length > 0
                onClicked: root.saveGameOptions()
              }
            }

            Rectangle {
              width: refreshLab.implicitWidth + 16
              height: 28
              radius: 6
              color: Qt.rgba(1, 1, 1, root.busy ? 0.05 : 0.12)
              border.color: Qt.rgba(1, 1, 1, 0.14)
              border.width: 1
              opacity: root.busy ? 0.45 : 1
              Text {
                id: refreshLab
                anchors.centerIn: parent
                text: "Refresh"
                color: root.fg
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                enabled: !root.busy
                onClicked: root.refreshList()
              }
            }
          }

          Text {
            width: parent.width
            text: root.busy ? "Working…" : root.statusText
            color: root.fg
            font.pixelSize: Style.font.caption
            opacity: 0.7
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
