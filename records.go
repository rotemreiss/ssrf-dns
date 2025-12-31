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

// RecordList is a helper type to handle both single object and list of objects
type RecordList []RecordConfig

// UnmarshalYAML implements custom unmarshaling to handle single object or list
func (rl *RecordList) UnmarshalYAML(value *yaml.Node) error {
	if value.Kind == yaml.SequenceNode {
		var records []RecordConfig
		if err := value.Decode(&records); err != nil {
			return err
		}
		*rl = records
		return nil
	}

	// Try single object
	var record RecordConfig
	if err := value.Decode(&record); err != nil {
		return err
	}
	*rl = []RecordConfig{record}
	return nil
}

// StaticRecordsConfig represents the top-level YAML structure
type StaticRecordsConfig struct {
	Records map[string]RecordList `yaml:"record"`
}

// LoadStaticRecords loads the YAML configuration from the given file path
func LoadStaticRecords(filePath string) (map[string][]RecordConfig, error) {
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

	// Convert map[string]RecordList to map[string][]RecordConfig
	result := make(map[string][]RecordConfig)
	for k, v := range config.Records {
		result[k] = v
	}

	return result, nil
}
