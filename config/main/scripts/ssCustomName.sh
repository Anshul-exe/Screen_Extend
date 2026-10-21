#!/bin/bash

# Giving the path for saving screenshot
screenshot_dir=~/clear_space/Media/screenshots
# Taking Screenshot using flameshot and storing it with a default name
default_name=$(date '+%Y-%m-%d_%H-%M-%S').png
flameshot gui -p "$screenshot_dir/$default_name"
# Copy the screenshot to clipboard.
# Use clipimg rather than xclip: xclip can advertise only ONE target, and
# Deskflow's clipboard understands only image/bmp -- so a PNG-only clipboard
# arrives as garbage on the other machine. clipimg (GTK) advertises image/png
# AND image/bmp at once, so local apps behave exactly as before while Deskflow
# picks up the BMP. Falls back to xclip where clipimg is not installed.
if [ -x "$HOME/.local/bin/clipimg" ]; then
  pkill -f "$HOME/.local/bin/clipimg" 2>/dev/null
  setsid "$HOME/.local/bin/clipimg" "$screenshot_dir/$default_name" >/dev/null 2>&1 &
  sleep 0.5 # let it load the file into memory before we may delete it below
else
  xclip -selection clipboard -t image/png -i "$screenshot_dir/$default_name"
fi
# Use zenity for GUI
# new_name=$(zenity --entry --title="Rename Screenshot" --text="Enter new name for the screenshot:" --entry-text="$default_name")
# Use Rofi for fast response
new_name=$(rofi -dmenu -p "Enter new name for screenshot:" -theme "$HOME/.config/rofi/todo.rasi" -no-fixed-num-lines <<<"$default_name")

# If the user provided a name, rename the screenshot and keep it
if [ ! -z "$new_name" ] && [ "$new_name" != "$default_name" ]; then
  # Add the .png extension if it's not provided
  if [[ "$new_name" != *.png ]]; then
    new_name="$new_name.png"
  fi
  mv "$screenshot_dir/$default_name" "$screenshot_dir/$new_name"
else
  # If no name provided or same as default, delete the file (it's already in clipboard)
  rm "$screenshot_dir/$default_name"
fi
