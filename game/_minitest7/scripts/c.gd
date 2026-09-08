extends Node

# NON-autoload script that references a bare autoload
func run():
	if Second:
		print("non-autoload sees Second")
