NAME    = sshfshop
BIN_DIR = ~/.local/bin

.PHONY: install uninstall

install:
	install -d $(BIN_DIR)
	install -m 755 -T $(NAME).sh $(BIN_DIR)/$(NAME)

uninstall:
	rm -f $(BIN_DIR)/$(NAME)