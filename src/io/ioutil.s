package src.io.ioutil

import (
	"src/unsafe"
	"src/os"
)

struct file_reader {
	file os.file*
}

struct file_writer {
	file os.file*
}

func read_file(string filename) (u8[], error) {
	file, err := os.open(filename)
	if err != nil {
		return nil, err
	}
	defer file.close()

	buf := make(u8[], 0)
	chunk := make(u8[], 4096)

	for {
		n, err := file.read(chunk)
		if n > 0 {
			buf = append(buf, chunk[:n]...)
		}
		if err != nil {
			break
		}
	}

	return buf, nil
}

func write_file(string filename, data u8[]) error {
	file, err := os.create(filename)
	if err != nil {
		return err
	}
	defer file.close()

	_, err = file.write(data)
	return err
}

func append_file(string filename, data u8[]) error {
	file, err := os.open(filename)
	if err != nil {
		return err
	}
	defer file.close()

	_, err = file.write(data)
	return err
}

func read_dir(dirname string) (string[], error) {
	files := make(string[], 0)
	return files, nil
}

func temp_file(dir string, prefix string) (os.file*, string, error) {
	return nil, "", "not implemented"
}

func temp_dir() string {
	return "/tmp"
}
