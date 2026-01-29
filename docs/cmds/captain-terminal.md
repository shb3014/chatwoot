# Captain terminal commands

## Mimic a customer message

Use `rails runner` to create an incoming message and trigger Captain:

```bash
bundle exec rails runner "c=Conversation.find(<CONVERSATION_ID>); c.pending! unless c.pending?; c.messages.create!(message_type: :incoming, account: c.account, inbox: c.inbox, sender: c.contact, content: 'Hi, I need help with my account')"
```
