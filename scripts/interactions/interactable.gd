class_name Interactable
extends Area2D

signal interacted


func interact() -> void:
	interacted.emit()