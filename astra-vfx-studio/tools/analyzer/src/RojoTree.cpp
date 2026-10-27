// astra-analyze - Rojo-Dateibaum -> Roblox-Instanzbaum
// SPDX-License-Identifier: MIT
//
// Abbildung nach Rojo-Konventionen (Rojo 7):
//   Verzeichnis                 -> Folder (Kinder = Eintraege)
//   Verzeichnis mit init.luau   -> ModuleScript (das Verzeichnis IST das Skript, uebrige Eintraege sind Kinder)
//   Verzeichnis mit init.server.luau / init.client.luau -> Script / LocalScript
//   X.luau                      -> ModuleScript "X"
//   X.server.luau / X.client.luau -> Script / LocalScript "X"
//   X.json / X.toml             -> ModuleScript "X" (Typ any)
//   X.model.json, X.rbxm(x), X.project.json, X.txt, X.csv -> Instanz "X" (nicht require-bar)
//   *.meta.json                 -> ignoriert
// Die Endung .lua wird ueberall gleichwertig zu .luau behandelt.

#include "RojoTree.h"

#include <algorithm>
#include <filesystem>
#include <system_error>

namespace fs = std::filesystem;

namespace astra
{

const char* RojoNode::className() const
{
    switch (kind)
    {
    case NodeKind::Folder:
        return "Folder";
    case NodeKind::ModuleScript:
        return "ModuleScript";
    case NodeKind::Script:
        return "Script";
    case NodeKind::LocalScript:
        return "LocalScript";
    case NodeKind::DataModule:
        return "ModuleScript";
    case NodeKind::Other:
        return "Instance";
    }
    return "Instance";
}

static bool endsWith(const std::string& s, const std::string& suffix)
{
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

static std::string stripSuffix(const std::string& s, const std::string& suffix)
{
    return s.substr(0, s.size() - suffix.size());
}

static std::string joinPath(const std::string& dir, const std::string& name)
{
    if (dir.empty() || dir == ".")
        return name;
    if (dir.back() == '/')
        return dir + name;
    return dir + "/" + name;
}

// Klassifiziert einen Dateinamen. Gibt false zurueck, wenn die Datei von Rojo ignoriert wird.
static bool classifyFile(const std::string& fileName, std::string& instanceName, NodeKind& kind)
{
    if (endsWith(fileName, ".meta.json"))
        return false;

    static const std::pair<const char*, NodeKind> luauSuffixes[] = {
        {".server.luau", NodeKind::Script},
        {".server.lua", NodeKind::Script},
        {".client.luau", NodeKind::LocalScript},
        {".client.lua", NodeKind::LocalScript},
        {".luau", NodeKind::ModuleScript},
        {".lua", NodeKind::ModuleScript},
    };
    for (const auto& [suffix, k] : luauSuffixes)
    {
        if (endsWith(fileName, suffix))
        {
            instanceName = stripSuffix(fileName, suffix);
            kind = k;
            return !instanceName.empty();
        }
    }

    static const char* otherSuffixes[] = {".model.json", ".project.json", ".rbxmx", ".rbxm", ".txt", ".csv"};
    for (const char* suffix : otherSuffixes)
    {
        if (endsWith(fileName, suffix))
        {
            instanceName = stripSuffix(fileName, suffix);
            kind = NodeKind::Other;
            return !instanceName.empty();
        }
    }

    static const char* dataSuffixes[] = {".json", ".toml"};
    for (const char* suffix : dataSuffixes)
    {
        if (endsWith(fileName, suffix))
        {
            instanceName = stripSuffix(fileName, suffix);
            kind = NodeKind::DataModule;
            return !instanceName.empty();
        }
    }

    return false;
}

static bool isInitFile(const std::string& fileName)
{
    return fileName == "init.luau" || fileName == "init.lua" || fileName == "init.server.luau" || fileName == "init.server.lua" ||
           fileName == "init.client.luau" || fileName == "init.client.lua" || fileName == "init.meta.json";
}

RojoNode* RojoTree::newNode(const std::string& name, NodeKind kind, const std::string& id, const std::string& sourcePath, RojoNode* parent)
{
    auto node = std::make_unique<RojoNode>();
    node->name = name;
    node->kind = kind;
    node->id = id;
    node->sourcePath = sourcePath;
    node->parent = parent;

    RojoNode* raw = node.get();
    nodes.push_back(std::move(node));
    byId[id] = raw;

    if (parent)
    {
        auto [it, inserted] = parent->children.emplace(name, raw);
        if (!inserted)
            warnings.push_back("duplicate instance name '" + name + "' in " + parent->id + " (" + it->second->id + " and " + id + "); first one wins");
    }

    return raw;
}

// Sucht die init-Datei eines Verzeichnisses. Rojo erlaubt nur eine.
static std::optional<std::pair<std::string, NodeKind>> findInit(const std::string& dirPath)
{
    static const std::pair<const char*, NodeKind> inits[] = {
        {"init.luau", NodeKind::ModuleScript},
        {"init.lua", NodeKind::ModuleScript},
        {"init.server.luau", NodeKind::Script},
        {"init.server.lua", NodeKind::Script},
        {"init.client.luau", NodeKind::LocalScript},
        {"init.client.lua", NodeKind::LocalScript},
    };

    for (const auto& [file, kind] : inits)
    {
        std::error_code ec;
        if (fs::is_regular_file(fs::path(dirPath) / file, ec))
            return std::make_pair(joinPath(dirPath, file), kind);
    }
    return std::nullopt;
}

void RojoTree::scanDirectory(RojoNode* dirNode, const std::string& dirPath, int depth)
{
    if (depth > 64)
    {
        warnings.push_back("directory depth > 64 at " + dirPath + " (symlink loop?); stopped");
        return;
    }

    std::vector<fs::directory_entry> entries;
    std::error_code ec;
    for (fs::directory_iterator it(dirPath, ec), end; !ec && it != end; it.increment(ec))
        entries.push_back(*it);

    std::sort(
        entries.begin(),
        entries.end(),
        [](const fs::directory_entry& a, const fs::directory_entry& b)
        {
            return a.path().filename().string() < b.path().filename().string();
        }
    );

    for (const fs::directory_entry& entry : entries)
    {
        std::string fileName = entry.path().filename().string();
        if (fileName.empty() || fileName[0] == '.')
            continue;

        std::string childPath = joinPath(dirPath, fileName);
        std::error_code ec2;

        if (entry.is_directory(ec2))
        {
            if (auto init = findInit(childPath))
            {
                RojoNode* child = newNode(fileName, init->second, init->first, init->first, dirNode);
                scanDirectory(child, childPath, depth + 1);
            }
            else
            {
                RojoNode* child = newNode(fileName, NodeKind::Folder, childPath + "/", "", dirNode);
                scanDirectory(child, childPath, depth + 1);
            }
            continue;
        }

        // init-Dateien gehoeren zum Verzeichnisknoten selbst
        if (dirNode->isLuau() && isInitFile(fileName))
            continue;
        if (fileName == "init.meta.json")
            continue;

        std::string instanceName;
        NodeKind kind;
        if (!classifyFile(fileName, instanceName, kind))
            continue;

        newNode(instanceName, kind, childPath, kind == NodeKind::Other ? "" : childPath, dirNode);
    }
}

bool RojoTree::build(const std::string& rootDir, std::string& error)
{
    std::error_code ec;
    if (!fs::is_directory(rootDir, ec))
    {
        error = "root directory does not exist: " + rootDir;
        return false;
    }

    rootDisplay = rootDir;
    while (rootDisplay.size() > 1 && rootDisplay.back() == '/')
        rootDisplay.pop_back();
    if (rootDisplay.rfind("./", 0) == 0 && rootDisplay.size() > 2)
        rootDisplay = rootDisplay.substr(2);

    rootAbsolute = fs::absolute(rootDisplay).lexically_normal().string();
    while (rootAbsolute.size() > 1 && rootAbsolute.back() == '/')
        rootAbsolute.pop_back();

    std::string rootName = fs::path(rootAbsolute).filename().string();
    if (auto init = findInit(rootDisplay))
        rootNode = newNode(rootName, init->second, init->first, init->first, nullptr);
    else
        rootNode = newNode(rootName, NodeKind::Folder, (rootDisplay == "/" ? std::string("/") : rootDisplay + "/"), "", nullptr);

    scanDirectory(rootNode, rootDisplay, 0);
    return true;
}

const RojoNode* RojoTree::findById(const std::string& id) const
{
    auto it = byId.find(id);
    return it == byId.end() ? nullptr : it->second;
}

std::vector<std::string> RojoTree::luauSourceFiles() const
{
    std::vector<std::string> result;
    for (const auto& node : nodes)
        if (node->isLuau())
            result.push_back(node->sourcePath);
    std::sort(result.begin(), result.end());
    return result;
}

std::string RojoTree::normalizePath(const std::string& path) const
{
    std::string abs = fs::absolute(path).lexically_normal().string();
    if (abs.size() > rootAbsolute.size() && abs.compare(0, rootAbsolute.size(), rootAbsolute) == 0 && abs[rootAbsolute.size()] == '/')
        return joinPath(rootDisplay, abs.substr(rootAbsolute.size() + 1));
    return path;
}

} // namespace astra
