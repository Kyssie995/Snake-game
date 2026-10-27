// astra-analyze - Roblox-spezifische Erweiterungen der globalen Typumgebung
// SPDX-License-Identifier: MIT
#pragma once

#include <string>
#include <unordered_set>
#include <vector>

namespace Luau
{
struct Frontend;
struct GlobalTypes;
struct TypeError;
} // namespace Luau

namespace astra
{

// Inhalt der "--#METADATA#{...}"-Zeile der luau-lsp-Definitionsdatei.
struct RobloxMetadata
{
    std::unordered_set<std::string> creatableInstances;
    std::unordered_set<std::string> services;
};

RobloxMetadata parseMetadata(const std::string& definitionsSource);

struct ExtensionOptions
{
    bool scriptIsAny = true;     // `script` als `any` typisieren
    bool dataModelServices = true; // game.Players, game.ReplicatedStorage, ... als Properties von DataModel
};

// Muss nach loadDefinitionFile und vor freeze(globals.globalTypes) aufgerufen werden.
// Haengt "magische" Funktionen an (Instance.new, GetService, IsA, FindFirstChildWhichIsA, Clone,
// GetPropertyChangedSignal), so wie luau-lsp es tut.
void installRobloxExtensions(
    Luau::Frontend& frontend,
    Luau::GlobalTypes& globals,
    const RobloxMetadata& metadata,
    const ExtensionOptions& options,
    std::vector<std::string>& warnings
);

// Liefert fuer UnknownProperty-Fehler auf Roblox-Klassen einen Vorschlag (" (meintest du 'Rate'?)"), sonst "".
std::string suggestionForError(const Luau::TypeError& error);

} // namespace astra
