import re

with open('lib/state.ts', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the inline generic type with a separate type alias
old_pattern = r'export const useSettings = create<\{\s*systemPrompt: string;\s*model: string;\s*voice: string;\s*isEasterEggMode: boolean;\s*activePersona: string;\s*setSystemPrompt: \(prompt: string\) => void;\s*setModel: \(model: string\) => void;\s*setVoice: \(voice: string\) => void;\s*setPersona: \(persona: string\) => void;\s*activateEasterEggMode: \(\) => void;\s*\}>\(set => \(\{'

new_text = '''type SettingsStore = {
  systemPrompt: string;
  model: string;
  voice: string;
  isEasterEggMode: boolean;
  activePersona: string;
  setSystemPrompt: (prompt: string) => void;
  setModel: (model: string) => void;
  setVoice: (voice: string) => void;
  setPersona: (persona: string) => void;
  activateEasterEggMode: () => void;
};

export const useSettings = create<SettingsStore>(set => ({'''

content = re.sub(old_pattern, new_text, content, flags=re.DOTALL)

with open('lib/state.ts', 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed!")

