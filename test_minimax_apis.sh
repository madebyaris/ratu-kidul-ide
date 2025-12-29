#!/bin/bash

API_KEY="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJHcm91cE5hbWUiOiJBcmlzIFNldGlhd2FuIiwiVXNlck5hbWUiOiJNYWRlYnlhcmlzIiwiQWNjb3VudCI6IiIsIlN1YmplY3RJRCI6IjE5OTczMDU3MDQ0NTY2NTUxMTUiLCJQaG9uZSI6IiIsIkdyb3VwSUQiOiIxOTk3MzA1NzA0NDQ4MjcwNjAzIiwiUGFnZU5hbWUiOiIiLCJNYWlsIjoiYXJpc3NldGlhLm1AZ21haWwuY29tIiwiQ3JlYXRlVGltZSI6IjIwMjUtMTItMTUgMjE6MjI6MzEiLCJUb2tlblR5cGUiOjQsImlzcyI6Im1pbmltYXgifQ.x-iQeyhJ-4AFCygNaxnUs8IzDqmoDKhqC1cZHiU2HZir7N_QxjNwch5I9VQBAGaXK5F7ESpDnWD49o0Ov-tXwPRCynDbiAogD0192ubh1RFvS2WD_HzjvIP2xtxa1pjDqumVDhfqsMPVYSODjn2xK3XL532kvXwVEwKHy1IPaN5_yF37MQxkBdsOcdPrkg1Md9oYwgW9QsjoolLa2N_aBZmp2IpNMHlBdHb48B3MTHXSfvwy_AX0Sms27LKit86Zz1nZmjTUoYYnjhNxo4jVSUAxltLfbGfTNAw2sxwU_bZK5uFiiyVKImHs0ftYVGhu4O9YOulyVGL3cg-IhAzhAQ"

echo "=========================================="
echo "Testing Anthropic-Compatible API"
echo "Endpoint: https://api.minimax.io/anthropic/v1/messages"
echo "=========================================="
echo ""

curl -X POST "https://api.minimax.io/anthropic/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "MiniMax-M2",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Say hello in one sentence"
          }
        ]
      }
    ],
    "max_tokens": 100,
    "stream": false
  }' 2>/dev/null | python3 -m json.tool

echo ""
echo ""
echo "=========================================="
echo "Testing OpenAI-Compatible API"
echo "Endpoint: https://api.minimax.io/v1/chat/completions"
echo "=========================================="
echo ""

curl -X POST "https://api.minimax.io/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "MiniMax-M2",
    "messages": [
      {
        "role": "user",
        "content": "Say hello in one sentence"
      }
    ],
    "max_tokens": 100,
    "stream": false
  }' 2>/dev/null | python3 -m json.tool

