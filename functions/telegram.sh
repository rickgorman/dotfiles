# Send a message to Telegram via stdin
# Usage:
#   echo "Hello world" | telegram
#   cat file.txt | telegram
#
# Requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID — either set in the current
# shell or in ~/.env (sourced automatically if the vars are not already present).

telegram() {
  local env_file="$HOME/.env"
  local help_text='
Add the following to your ~/.env file:

TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
'

  # Source ~/.env if the vars aren't already set in the current shell
  if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
    [[ -f "$env_file" ]] && source "$env_file"
  fi

  if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
    echo "Error: Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID in ~/.env"
    echo "$help_text"
    echo "To get your bot token:"
    echo "  1. Open Telegram and search for @BotFather"
    echo "  2. Send /newbot and follow the prompts"
    echo "  3. Copy the token provided"
    echo "  https://t.me/BotFather"
    echo ""
    echo "To get your chat ID:"
    echo "  1. Send any message to your bot"
    echo "  2. Visit: https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates"
    echo "  3. Find your chat id in the response under result[].message.chat.id"
    return 1
  fi

  local message
  message=$(cat)

  if [[ -z "$message" ]]; then
    echo "Error: No message provided via stdin"
    echo "Usage: echo 'your message' | telegram"
    return 1
  fi

  local response
  response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg chat_id "$TELEGRAM_CHAT_ID" --arg text "$message" \
      '{chat_id: $chat_id, text: $text}')")

  echo "$response"

  if echo "$response" | jq -e '.ok == true' > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}
