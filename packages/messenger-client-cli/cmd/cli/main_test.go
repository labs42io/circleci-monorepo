package main

import "testing"

func TestMain(t *testing.T) {
	expected := "Hello World"
	got := returnMessage()
	if got != expected {
		t.Fatalf("Expected %s, got %s", expected, got)
	}
}
