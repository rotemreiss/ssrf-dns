package main

import (
	"fmt"
	"io/ioutil"

	"gopkg.in/yaml.v3"
)

// RecordConfig represents a single DNS record configuration
type RecordConfig struct {
	Type  string `yaml:"type"`
	Value string `yaml:"value"`
}

// StaticRecordsConfig represents the top-level YAML structure
type StaticRecordsConfig struct {
	Records map[string]RecordConfig `yaml:"record"`
}

// LoadStaticRecords loads the YAML configuration from the given file path
func LoadStaticRecords(filePath string) (map[string]RecordConfig, error) {
	if filePath == "" {
		return nil, nil // No file specified is not an error
	}

	data, err := ioutil.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	var config StaticRecordsConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse YAML: %w", err)
	}

	return config.Records, nil
}
