class_name Interactable
extends Area2D

signal interacted(actor: Node)


func interact(actor: Node) -> void:
	interacted.emit(actor)
