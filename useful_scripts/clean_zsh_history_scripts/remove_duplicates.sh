cp ~/.zsh_history ./DOT_zsh_history
awk -F';' '{print $2}' DOT_zsh_history > temp_commands.txt
awk '!seen[$0]++' temp_commands.txt > temp_unique_commands.txt
awk -F';' 'NR==FNR {cmds[$0]; next} $2 in cmds {print $0; delete cmds[$2]}' temp_unique_commands.txt DOT_zsh_history > final.txt
mv final.txt DOT_zsh_history
