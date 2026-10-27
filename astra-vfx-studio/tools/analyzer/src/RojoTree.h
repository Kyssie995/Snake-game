// astra-analyze - Rojo-Dateibaum -> Roblox-Instanzbaum (fuer require(script...)-Aufloesung)
// SPDX-License-Identifier: MIT
#pragma once

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace astra
{

enum class NodeKind
{
    Folder,       // Verzeichnis ohne init.* -> Folder
    ModuleScript, // X.luau / init.luau
    Script,       // X.server.luau / init.server.luau
    LocalScript,  // X.client.luau / init.client.luau
    DataModule,   // X.json / X.toml -> ModuleScript, Typ `any`
    Other,        // .txt, .csv, .rbxm, .model.json, ... (nicht require-bar)
};

struct RojoNode
{
    std::string name;      // Instanzname (Name-Property)
    NodeKind kind = NodeKind::Folder;
    std::string id;        // eindeutiger ModuleName im Frontend (Dateipfad bzw. Verzeichnispfad)
    std::string sourcePath; // Quelldatei (leer bei Folder)
    RojoNode* parent = nullptr;
    std::map<std::string, RojoNode*> children; // Name -> Kind (bei Duplikaten gewinnt der erste)

    bool isLuau() const
    {
        return kind == NodeKind::ModuleScript || kind == NodeKind::Script || kind == NodeKind::LocalScript;
    }
    const char* className() const;
};

class RojoTree
{
public:
    // Baut den Baum fuer rootDir. Gibt false + Fehlermeldung zurueck, wenn rootDir nicht existiert.
    bool build(const std::string& rootDir, std::string& error);

    const RojoNode* root() const
    {
        return rootNode;
    }
    const RojoNode* findById(const std::string& id) const;

    // Alle Luau-Quelldateien (ModuleScript/Script/LocalScript) in deterministischer Reihenfolge.
    std::vector<std::string> luauSourceFiles() const;

    // Normalisiert einen beliebigen (relativen/absoluten) Dateipfad auf die im Baum verwendete Schreibweise,
    // sofern er unterhalb von root liegt. Sonst wird der Pfad unveraendert zurueckgegeben.
    std::string normalizePath(const std::string& path) const;

    const std::string& rootPath() const
    {
        return rootDisplay;
    }

    std::vector<std::string> warnings;

private:
    RojoNode* newNode(const std::string& name, NodeKind kind, const std::string& id, const std::string& sourcePath, RojoNode* parent);
    void scanDirectory(RojoNode* dirNode, const std::string& dirPath, int depth);

    std::vector<std::unique_ptr<RojoNode>> nodes;
    std::unordered_map<std::string, RojoNode*> byId;
    RojoNode* rootNode = nullptr;
    std::string rootDisplay;  // root wie vom Benutzer angegeben (ohne abschliessenden '/')
    std::string rootAbsolute; // absolut + normalisiert
};

} // namespace astra
