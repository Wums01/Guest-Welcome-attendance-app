#!/bin/bash
cd /c/Users/DELL.COM/Desktop/Darey/Guest-Welcome-attendance-app/flutter_app
flutter analyze > /c/Users/DELL.COM/Desktop/Darey/Guest-Welcome-attendance-app/analyze_output.txt 2>&1
echo "exit_code=$?" >> /c/Users/DELL.COM/Desktop/Darey/Guest-Welcome-attendance-app/analyze_output.txt
