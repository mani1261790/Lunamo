import MarimoDomain

func textOutput(_ text: String, channel: OutputChannel = .output) -> MarimoOutput {
  MarimoOutput(channel: channel, mimeType: "text/plain", data: .string(text))
}
