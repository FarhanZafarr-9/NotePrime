
import sys

def check_brackets(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    stack = []
    brackets = {'(': ')', '{': '}', '[': ']'}
    
    for i, char in enumerate(content):
        if char in brackets:
            stack.append((char, i))
        elif char in brackets.values():
            if not stack:
                print(f"Extra closing bracket '{char}' at index {i}")
                continue
            top, pos = stack.pop()
            if brackets[top] != char:
                print(f"Mismatched bracket '{char}' at index {i}, matches '{top}' at index {pos}")
                
    if stack:
        for b, pos in stack:
            print(f"Unclosed bracket '{b}' at index {pos}")

if __name__ == "__main__":
    check_brackets(sys.argv[1])
