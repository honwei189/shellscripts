import os
import subprocess
import sys
from tqdm import tqdm

"""
PHP Syntax Checker

This script recursively scans a given directory for PHP files and checks for syntax errors, warnings, and deprecations.
It generates a log file with all identified issues.

Usage:
    python check_php_syntax.py [directory]

Arguments:
    directory: Optional. The directory to check for PHP syntax errors. If not provided, the script will prompt for it.

Output:
    - A progress bar displaying the checking progress.
    - A summary of total PHP files checked, number of files with errors, and total errors/warnings.
    - A log file (php_syntax_errors.log) with detailed information on all identified issues.

Dependencies:
    - tqdm: Install using `pip install tqdm`
"""

def check_php_syntax(directory, log_file):
    errors_warnings = []  # List to store all errors and warnings
    total_files = 0  # Counter for total number of PHP files
    problem_files = 0  # Counter for files with issues
    total_errors = 0  # Counter for total errors and warnings
    
    # Recursively scan the directory to count PHP files
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.php'):
                total_files += 1

    # Use progress bar to show the file checking progress
    with tqdm(total=total_files, desc="Checking PHP files", unit="file") as pbar:
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.endswith('.php'):
                    filepath = os.path.join(root, file)
                    # Run PHP syntax check command
                    result = subprocess.run(f'php -l "{filepath}"', stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, shell=True)
                    output = result.stdout + result.stderr
                    # Uncomment for debugging
                    # print(f"Checking file: {filepath}")
                    # print(f"Output: {output}")
                    # If the output contains errors or warnings, log the file
                    if any(keyword in output for keyword in ["Deprecated:", "Parse error:", "Warning:"]):
                        errors_warnings.append(f"{filepath}:\n{output.strip()}\n")
                        problem_files += 1
                        total_errors += output.strip().count("Deprecated:") + output.strip().count("Parse error:") + output.strip().count("Warning:")
                    pbar.update(1)

    # Write errors and warnings to the log file
    if errors_warnings:
        with open(log_file, 'w', encoding='utf-8') as f:
            for warning in errors_warnings:
                f.write(warning + '\n')
    
    return total_files, problem_files, total_errors

def main():
    log_file = "php_syntax_errors.log"
    # Check if a directory path was provided as a command-line argument
    if len(sys.argv) > 1:
        directory = sys.argv[1]
    else:
        directory = input("Enter the directory to check for PHP syntax errors: ")
    
    if not os.path.isdir(directory):
        print("The provided directory does not exist.")
        return

    total_files, problem_files, total_errors = check_php_syntax(directory, log_file)
    print(f"Total PHP files checked: {total_files}")
    print(f"Files with errors: {problem_files}")
    print(f"Total errors/warnings: {total_errors}")

if __name__ == "__main__":
    main()
