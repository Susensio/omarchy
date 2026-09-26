echo "Keep ~/Work as the projects directory on installs that already use it"

[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
current=${XDG_PROJECTS_DIR:-}
current=${current%/}

# Anything else is somewhere of the user's own. $HOME is xdg-user-dirs resetting
# a missing dir, and ~/Projects may be its 0.20 default rather than a choice.
if [[ -n $current && $current != "$HOME" && $current != "$HOME/Projects" ]]; then
  echo "Projects directory already set to $current"
elif [[ -d ~/Work ]]; then
  xdg-user-dirs-update --set PROJECTS "$HOME/Work"
  echo "~/Work stays your projects directory. To switch to the new ~/Projects standard:"
  echo "  mv -T ~/Work ~/Projects && xdg-user-dirs-update --set PROJECTS ~/Projects"
  echo "Anything that saved a ~/Work path keeps pointing there: git worktrees, mise trust,"
  echo "zoxide history, editor recent files and open terminals. Check those after moving."
else
  xdg-user-dirs-update --set PROJECTS "$HOME/Projects"
fi
