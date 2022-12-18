#!/bin/bash

if [[ -L ~/.zshrc.local ]]; then
  rm ~/.zshrc.local
  ln -s ~/dotfiles-local/.zshrc ~/.zshrc.local
fi

if [[ -L ~/.zshenv.local ]]; then
  rm ~/.zshenv.local
  ln -s ~/dotfiles-local/.zshrc ~/.zshenv.local
fi

