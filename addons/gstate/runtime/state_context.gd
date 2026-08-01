@tool
class_name StateContext
extends Resource

## Base type for per-StateMachine runtime data.
##
## Create a typed subclass with exported properties, then assign an instance to
## StateMachine.initial_context. The machine duplicates it on every start.
