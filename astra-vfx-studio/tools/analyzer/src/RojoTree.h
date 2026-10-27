// astra-analyze - Rojo-Dateibaum / Rojo-Projektdatei -> Roblox-Instanzbaum (fuer require(script...)-Aufloesung)
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

struct JsonValue;

enum class NodeKind
{
    Folder,       // Verzeichnis ohne init.* -> Folder
    ModuleScript, // X.luau / init.luau
    Script,       // X.server.luau / init.server.luau
    LocalScript,  // X.client.luau / init.client.luau
    DataModule,   // X.json / X.toml -> ModuleScript, Typ `any`
    Other,        // .txt, .csv, .rbxm, .model.json, $className-Knoten, ... (nicht require-bar)
};

struct RojoNode
{
    std::string name;       // Instanzname (Name-Property)
    NodeKind kind = NodeKind::Folder;
    std::string id;         // eindeutiger ModuleName im Frontend (Dateipfad bzw. Verzeichnispfad)
    std::string sourcePath; // Quelldatei (leer bei Folder/Other)
    std::string classNameOverride; // aus "$className" der Projektdatei
    RojoNode* parent = nullptr;
    std::map<std::string, RojoNode*> children; // Name -> Kind (bei Duplikaten gewinnt der erste)

    bool isLuau() const
    {
        return kind == NodeKind::ModuleScript || kind == NodeKind::Script || kind == NodeKind::LocalScript;
    }
    std::string className() const;
};

class RojoTree
{
public:
    // --root: baut den Baum fuer ein Quellverzeichnis (das Verzeichnis selbst ist die Wurzelinstanz).
    bool build(const std::string& rootDir, std::string& error);

    // --project: baut den Baum aus einer Rojo-Projektdatei (default.project.json). Pfade ("$path")
    // sind relativ zum Verzeichnis der Projektdatei.
    bool buildFromProject(const std::string& projectFile, std::string& error);

    const RojoNode* root() const
    {
        return rootNode;
    }
    const RojoNode* findById(const std::string& id) const;

    // Alle Luau-Quelldateien (ModuleScript/Script/LocalScript) im Baum, sortiert und ohne Duplikate.
    std::vector<std::string> luauSourceFiles() const;

    // Bildet einen beliebigen (relativen/absoluten) Dateipfad auf die im Baum verwendete Schreibweise ab,
    // sofern die Datei im Baum vorkommt. Sonst wird der Pfad unveraendert zurueckgegeben.
    std::string normalizePath(const std::string& path) const;

    std::vector<std::string> warnings;

private:
    RojoNode* newNode(const std::string& name, NodeKind kind, const std::string& id, const std::string& sourcePath, RojoNode* parent);
    RojoNode* addDirectory(const std::string& name, const std::string& dirPath, RojoNode* parent, int depth);
    RojoNode* addPath(const std::string& name, const std::string& fsPath, RojoNode* parent, int depth);
    RojoNode* addProjectFile(const std::string& name, const std::string& projectFile, RojoNode* parent, int depth, std::string* error);
    RojoNode* addProjectNode(
        const std::string& name,
        const JsonValue& node,
        const std::string& baseDir,
        const std::string& instancePath,
        RojoNode* parent,
        int depth
    );
    void scanDirectory(RojoNode* dirNode, const std::string& dirPath, int depth);
    void finish();

    std::vector<std::unique_ptr<RojoNode>> nodes;
    std::unordered_map<std::string, RojoNode*> byId;
    std::unordered_map<std::string, std::string> absoluteToId; // absoluter Quellpfad -> id
    RojoNode* rootNode = nullptr;
};

} // namespace astra
