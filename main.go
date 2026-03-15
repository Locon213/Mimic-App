// Mimic Protocol Client - Go Mobile Backend
// This package provides the backend service for the Flutter mobile app.
// The main entry point is in the mobile package for gomobile bind.
package main

import (
	"fmt"
	"log"

	"github.com/Locon213/Mimic-App/mobile"
)

func main() {
	fmt.Println("Mimic Protocol Client - Go Mobile Backend")
	fmt.Println("This binary is built for gomobile bind.")
	fmt.Println("Use the mobile package to create iOS/Android libraries.")

	// Example usage (for testing):
	client := mobile.NewMimicClient()
	fmt.Printf("Mimic Client Version: %s\n", client.GetVersion())
	log.Println("Mimic backend initialized successfully")
}
