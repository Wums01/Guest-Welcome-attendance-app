import subprocess, sys, os

os.chdir('/c/Users/DELL.COM/Desktop/Darey/Guest-Welcome-attendance-app/flutter_app')

try:
    result = subprocess.run(
        ['/c/flutter/bin/flutter', 'analyze', '--no-pub'],
        capture_output=True,
        text=True,
        timeout=180
    )
    with open('/c/Users/DELL.COM/Desktop/Darey/Guest-Welcome-attendance-app/flutter_analyze_out.txt', 'w') as f:
        f.write('STDOUT:\n')
        f.write(result.stdout)
        f.write('\nSTDERR:\n')
        f.write(result.stderr)
        f.write('\nEXIT CODE: ' + str(result.returncode) + '\n')
    print('Done, exit code:', result.returncode)
except subprocess.TimeoutExpired:
    print('TIMEOUT after 180s')
except Exception as e:
    print('ERROR:', str(e))
