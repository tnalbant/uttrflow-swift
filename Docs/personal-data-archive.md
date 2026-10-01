# Personal data archive

The Dictation tab in Settings can export the personal dictionary and snippets to a
versioned JSON file and import that file on another profile or Mac. The archive is
created only after the user chooses a destination; import reads only the file the
user chooses. There is no sync or automatic upload.

The file contains dictionary spellings and pronunciations, their origin and usage
counters, snippet triggers and expansion text, and their dates and usage counters.
Anyone who can read the chosen file can read that content. Uttrflow writes the
export with owner-only file permissions.

Import validates the complete versioned archive before writing either store. It
merges by case-insensitive dictionary spelling and normalized snippet trigger,
keeps existing entries when they collide, and reports how many duplicates it
skipped. A malformed or unsupported archive is refused without changing either
list. An import that would exceed the dictionary's inferred-word limit is also
refused before writing either list. The archive schema is version 1; incompatible
future formats must use a new version rather than silently guessing at fields.
