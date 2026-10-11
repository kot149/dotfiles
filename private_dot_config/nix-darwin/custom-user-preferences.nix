{ ... }:
let
  shift = 131072;
  control = 262144;
  option = 524288;
  command = 1048576;
  arrow = {
    left = 123;
    right = 124;
    down = 125;
    up = 126;
  };
in
{
  system.defaults.CustomUserPreferences = {
    "com.knollsoft.Rectangle" = {
      SUEnableAutomaticChecks = false;
      allowAnyShortcut = true;
      alternateDefaultShortcuts = false;
      doubleClickTitleBar = 3;
      hideMenubarIcon = false;
      landscapeSnapAreas = ''[7,{"compound":-4},3,{"action":16},2,{"action":2},1,{"action":15},4,{"compound":-2},5,{"compound":-3},8,{"action":14},6,{"action":13}]'';
      launchOnLogin = true;
      subsequentExecutionMode = 2;
      windowSnapping = 1;

      leftHalf = {
        keyCode = arrow.left;
        modifierFlags = control + command;
      };
      rightHalf = {
        keyCode = arrow.right;
        modifierFlags = control + command;
      };
      maximize = {
        keyCode = arrow.up;
        modifierFlags = control + command;
      };
      restore = {
        keyCode = arrow.down;
        modifierFlags = control + command;
      };
      almostMaximize = {
        keyCode = arrow.up;
        modifierFlags = control + shift;
      };
      nextDisplay = {
        keyCode = arrow.right;
        modifierFlags = control + shift;
      };
      previousDisplay = {
        keyCode = arrow.left;
        modifierFlags = control + shift;
      };
      reflowTodo = {
        keyCode = 45; # N
        modifierFlags = control + option;
      };
      toggleTodo = {
        keyCode = 11; # B
        modifierFlags = control + option;
      };

      # Empty dictionaries disable these shortcuts.
      bottomHalf = { };
      bottomLeft = { };
      bottomRight = { };
      center = { };
      larger = { };
      maximizeHeight = { };
      smaller = { };
      topHalf = { };
      topLeft = { };
      topRight = { };
    };

    "com.ethanbills.DockDoor" = {
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
      SUSendProfileInfo = false;
      disableImagePreview = false;
      dockBackgroundMaterial = "ultraThick";
      dockBackgroundStyle = "frostedMaterial";
      enableShiftWindowSwitcherPlacement = false;
      globalPaddingMultiplier = 0.5;
      includeHiddenWindowsInSwitcher = true;
      requireShiftTabToGoBack = true;
      showAnimations = false;
      showWindowlessAppsInSwitcher = false;
      uniformCardRadius = false;
      unselectedContentOpacity = 1.0;
    };

    "com.lwouis.alt-tab-macos" = {
      previousWindowShortcut = "⇧⇥"; # Shift+Tab
    };
  };
}
