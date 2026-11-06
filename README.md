# UnivaPayment App

Merchant Android app for UnivaPayment (Flutter, with the SMS receiver in Kotlin).

Current state: an SMS probe. It reads only bKash and Nagad SMS, captures new ones with the app closed, and produces a masked report of their formats. Nothing leaves the phone yet. Pairing and sending SMS to the server come next.

`flutter test` runs the masking and analysis tests.
