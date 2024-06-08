#!/bin/sh

# Function to echo and run commands
run_command() {
    echo "$@"
    "$@"
}

# Ensure that Siri usage data is not shared
run_command defaults write com.apple.assistant.support "Assistant Enabled" -bool false
run_command defaults write com.apple.Siri "DefaultsDisabled" -bool true
run_command defaults write com.apple.Siri "VoiceTriggerEnabled" -bool false
run_command defaults write com.apple.Siri "UserHasDeclinedEnable" -bool true
run_command defaults write com.apple.Siri "Events" -dict-add "enabled" -bool false

# Disable Siri status menu
run_command defaults write com.apple.Siri "StatusMenuVisible" -bool false

# Disable "Hey Siri" feature
run_command defaults write com.apple.assistant.backedup "Use device speaker for TTS" -int 3

# Disable Siri data collection
run_command defaults write com.apple.Siri "UserHasDeclinedEnableDataSharing" -bool true

# Remove Siri from the menu bar
run_command defaults write com.apple.systemuiserver "NSStatusItem Visible Siri" -bool false
run_command killall SystemUIServer

# Disable Dictation (if related to Siri)
run_command defaults write com.apple.speech.recognition.AppleSpeechRecognition.prefs DictationIMMasterDictationEnabled -bool false
run_command defaults write com.apple.speech.recognition.AppleSpeechRecognition.prefs DictationIMIntroMessagePresented -bool false

# Prevent Siri-related processes from starting at login
run_command sudo defaults write /Library/Preferences/com.apple.assistant.backedup "RTREnabled" -bool false
run_command sudo defaults write /Library/Preferences/com.apple.assistant.backedup "Siri Data Sharing Opt-In Status" -int 2
run_command sudo defaults write /Library/Preferences/com.apple.Siri.plist LockscreenSiriEnabled -bool false

# Unload Siri launch agents
run_command sudo launchctl disable system/com.apple.assistant_service.plist
run_command sudo launchctl disable system/com.apple.assistantd.plist
run_command sudo launchctl disable system/com.apple.Siri.agent.plist
run_command sudo launchctl disable system/com.apple.Siri.plist
run_command sudo launchctl bootout system/com.apple.assistant_service.plist
run_command sudo launchctl bootout system/com.apple.assistantd.plist
run_command sudo launchctl bootout system/com.apple.Siri.agent.plist
run_command sudo launchctl bootout system/com.apple.Siri.plist

# Clean any Siri saved preferences
run_command rm -rf ~/Library/Preferences/com.apple.assistant.plist
run_command rm -rf ~/Library/Preferences/com.apple.Siri.plist
run_command rm -rf ~/Library/Caches/com.apple.Siri

run_command killall Siri
run_command killall Assistant
run_command killall assistantd

echo "Do not forget to come back to this script and run the command to check the defaults."
# Check Siri status
# defaults read com.apple.assistant.support "Assistant Enabled"
# defaults read com.apple.Siri "StatusMenuVisible"
# defaults read com.apple.assistant.backedup "Use device speaker for TTS"
# defaults read com.apple.Siri "UserHasDeclinedEnableDataSharing"

# prompt user to reboot computer
response=$(osascript -e 'tell app "System Events" to display dialog "Would you like to reboot your computer now to apply all changes?" buttons {"Cancel", "Reboot"} default button "Reboot"')
button_clicked=$(echo "$response" | awk -F': ' '{print $2}')

if [ "$button_clicked" = "Reboot" ]; then
    run_command sudo shutdown -r now
else
    echo "Reboot cancelled by user."
fi

