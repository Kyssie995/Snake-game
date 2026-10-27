// astra-analyze - Rojo-Dateibaum / Rojo-Projektdatei -> Roblox-Instanzbaum
// SPDX-License-Identifier: MIT
//
// Abbildung nach Rojo-Konventionen (Rojo 7):
//   Verzeichnis                 -> Folder (Kinder = Eintraege)
//   Verzeichnis mit init.luau   -> ModuleScript (das Verzeichnis IST das Skript, uebrige Eintraege sind Kinder)
//   Verzeichnis mit init.server.luau / init.client.luau -> Script / LocalScript
//   Verzeichnis mit default.project.json -> der Baum dieser Projektdatei (verschachteltes Projekt)
//   X.luau                      -> ModuleScript "X"
//   X.server.luau / X.client.luau -> Script / LocalScript "X"
//   X.json / X.toml             -> ModuleScript "X" (Typ any)
//   X.project.json              -> verschachteltes Projekt "X"
//   X.model.json, X.rbxm(x), X.txt, X.csv -> Instanz "X" (nicht require-bar)
//   *.meta.json, versteckte Dateien (".xyz") -> ignoriert
// Die Endung .lua wird ueberall gleichwertig zu .luau behandelt.
//
// Projektdateien (Teilmenge): Knoten mit "$path" (Datei oder Verzeichnis, auch {"optional": "..."}),
// "$className" und Kindknoten (Schluessel = Instanzname). Der Instanzname eines "$path"-Knotens ist immer
// sein Schluessel im Baum, nicht der Datei-/Verzeichnisname. Andere "$"-Felder werden ignoriert.

#include "RojoTree.h"

#include "Json.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>
#include <system_error>

namespace fs = std::filesystem;

namespace astra
{

static const int kMaxDepth = 64;
static const char kNodePrefix[] = "\x01node\x01";

std::string RojoNode::className() const
{
    if (!classNameOverride.empty())
        return classNameOverride;
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

// "./src//Plugin/" -> "src/Plugin", "a/../b" -> "b", "" -> "."
static std::string cleanPath(const std::string& path)
{
    std::string p = fs::path(path.empty() ? "." : path).lexically_normal().generic_string();
    while (p.size() > 1 && p.back() == '/')
        p.pop_back();
    if (p.empty())
        p = ".";
    return p;
}

static std::string dirId(const std::string& dirPath)
{
    if (dirPath == ".")
        return "./";
    return dirPath.back() == '/' ? dirPath : dirPath + "/";
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

    static const char* otherSuffixes[] = {".model.json", ".rbxmx", ".rbxm", ".txt", ".csv"};
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

    if (!byId.emplace(id, raw).second)
        warnings.push_back(id + " is mapped more than once in the instance tree; `script` in that file refers to the first occurrence");

    if (parent)
    {
        auto [it, inserted] = parent->children.emplace(name, raw);
        if (!inserted)
            warnings.push_back("duplicate instance name '" + name + "' in " + parent->id + " (" + it->second->id + " and " + id + "); first one wins");
    }

    return raw;
}

RojoNode* RojoTree::addDirectory(const std::string& name, const std::string& dirPath, RojoNode* parent, int depth)
{
    if (depth > kMaxDepth)
    {
        warnings.push_back("instance tree deeper than " + std::to_string(kMaxDepth) + " at " + dirPath + " (symlink loop?); stopped");
        return nullptr;
    }

    // Ein Verzeichnis mit default.project.json ist fuer Rojo das darin beschriebene Projekt.
    std::error_code ec;
    std::string nestedProject = joinPath(dirPath, "default.project.json");
    if (parent && fs::is_regular_file(nestedProject, ec))
        return addProjectFile(name, nestedProject, parent, depth + 1, nullptr);

    RojoNode* node;
    if (auto init = findInit(dirPath))
        node = newNode(name, init->second, init->first, init->first, parent);
    else
        node = newNode(name, NodeKind::Folder, dirId(dirPath), "", parent);

    scanDirectory(node, dirPath, depth + 1);
    return node;
}

void RojoTree::scanDirectory(RojoNode* dirNode, const std::string& dirPath, int depth)
{
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
            addDirectory(fileName, childPath, dirNode, depth);
            continue;
        }

        // init-Dateien gehoeren zum Verzeichnisknoten selbst
        if (isInitFile(fileName) || fileName == "default.project.json")
            continue;

        if (endsWith(fileName, ".project.json"))
        {
            addProjectFile(stripSuffix(fileName, ".project.json"), childPath, dirNode, depth, nullptr);
            continue;
        }

        std::string instanceName;
        NodeKind kind;
        if (!classifyFile(fileName, instanceName, kind))
            continue;

        newNode(instanceName, kind, childPath, kind == NodeKind::Other ? "" : childPath, dirNode);
    }
}

RojoNode* RojoTree::addPath(const std::string& name, const std::string& fsPath, RojoNode* parent, int depth)
{
    std::error_code ec;
    if (fs::is_directory(fsPath, ec))
        return addDirectory(name, fsPath, parent, depth);

    if (!fs::is_regular_file(fsPath, ec))
    {
        warnings.push_back("$path does not exist: " + fsPath);
        return nullptr;
    }

    std::string fileName = fs::path(fsPath).filename().string();
    if (endsWith(fileName, ".project.json"))
        return addProjectFile(name, fsPath, parent, depth + 1, nullptr);

    std::string ignoredName;
    NodeKind kind;
    if (!classifyFile(fileName, ignoredName, kind))
    {
        if (!endsWith(fileName, ".meta.json"))
            warnings.push_back("unsupported file type for $path " + fsPath + " (treated as a non-script instance)");
        return newNode(name, NodeKind::Other, fsPath, "", parent);
    }

    // Instanzname = Schluessel im Projektbaum, nicht der Dateiname
    return newNode(name, kind, fsPath, kind == NodeKind::Other ? "" : fsPath, parent);
}

RojoNode* RojoTree::addProjectFile(const std::string& name, const std::string& projectFile, RojoNode* parent, int depth, std::string* error)
{
    auto report = [&](const std::string& msg) -> RojoNode*
    {
        if (error)
            *error = msg;
        else
            warnings.push_back(msg);
        return nullptr;
    };

    if (depth > kMaxDepth)
        return report("project nesting deeper than " + std::to_string(kMaxDepth) + " at " + projectFile);

    std::ifstream in(projectFile, std::ios::binary);
    if (!in)
        return report("cannot read project file " + projectFile);
    std::stringstream ss;
    ss << in.rdbuf();
    std::string text = ss.str();

    std::string parseError;
    std::optional<JsonValue> json = JsonParser(text).parse(parseError);
    if (!json)
        return report("invalid JSON in project file " + projectFile + ": " + parseError);

    const JsonValue* tree = json->find("tree");
    if (!tree || !tree->isObject())
        return report("project file " + projectFile + " has no \"tree\" object");

    std::string instanceName = name;
    if (instanceName.empty())
    {
        const JsonValue* projectName = json->find("name");
        instanceName = projectName && projectName->isString() ? projectName->string : fs::path(projectFile).stem().stem().string();
    }

    std::string baseDir = cleanPath(fs::path(projectFile).parent_path().generic_string());
    return addProjectNode(instanceName, *tree, baseDir, instanceName, parent, depth + 1);
}

RojoNode* RojoTree::addProjectNode(
    const std::string& name,
    const JsonValue& node,
    const std::string& baseDir,
    const std::string& instancePath,
    RojoNode* parent,
    int depth
)
{
    if (depth > kMaxDepth)
    {
        warnings.push_back("project tree deeper than " + std::to_string(kMaxDepth) + " at " + instancePath + "; stopped");
        return nullptr;
    }

    std::string className;
    if (const JsonValue* cn = node.find("$className"); cn && cn->isString())
        className = cn->string;

    RojoNode* result = nullptr;

    if (const JsonValue* pathValue = node.find("$path"))
    {
        std::string rawPath;
        bool optional = false;
        if (pathValue->isString())
            rawPath = pathValue->string;
        else if (const JsonValue* opt = pathValue->find("optional"); opt && opt->isString())
        {
            rawPath = opt->string;
            optional = true;
        }

        if (!rawPath.empty())
        {
            std::string fsPath = fs::path(rawPath).is_absolute() ? cleanPath(rawPath) : cleanPath(joinPath(baseDir, rawPath));
            std::error_code ec;
            if (!(optional && !fs::exists(fsPath, ec)))
                result = addPath(name, fsPath, parent, depth);
        }
        else
            warnings.push_back("unsupported $path value at " + instancePath);
    }

    if (!result)
    {
        // Reiner $className-Knoten (z.B. Folder, ReplicatedStorage) oder fehlender $path
        NodeKind kind = (className.empty() || className == "Folder") ? NodeKind::Folder : NodeKind::Other;
        result = newNode(name, kind, std::string(kNodePrefix) + instancePath, "", parent);
    }

    if (!className.empty() && !result->isLuau() && result->kind != NodeKind::DataModule)
        result->classNameOverride = className;

    for (const auto& [key, child] : node.object)
    {
        if (key.empty() || key[0] == '$' || !child.isObject())
            continue;
        addProjectNode(key, child, baseDir, instancePath + "." + key, result, depth + 1);
    }

    return result;
}

void RojoTree::finish()
{
    for (const auto& node : nodes)
    {
        if (node->sourcePath.empty())
            continue;
        std::string abs = fs::absolute(node->sourcePath).lexically_normal().string();
        absoluteToId.emplace(abs, node->id);
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

    std::string rootPath = cleanPath(rootDir);
    std::string rootName = fs::absolute(rootPath).lexically_normal().filename().string();
    if (rootName.empty())
        rootName = fs::absolute(rootPath).lexically_normal().parent_path().filename().string();

    // parent == nullptr: eine default.project.json im Root wird hier bewusst nicht ausgewertet (dafuer --project)
    rootNode = addDirectory(rootName, rootPath, nullptr, 0);
    if (!rootNode)
    {
        error = "cannot build instance tree for " + rootDir;
        return false;
    }
    finish();
    return true;
}

bool RojoTree::buildFromProject(const std::string& projectFile, std::string& error)
{
    std::error_code ec;
    if (!fs::is_regular_file(projectFile, ec))
    {
        error = "project file does not exist: " + projectFile;
        return false;
    }

    rootNode = addProjectFile("", cleanPath(projectFile), nullptr, 0, &error);
    if (!rootNode)
        return false;
    finish();
    return true;
}

const RojoNode* RojoTree::findById(const std::string& id) const
{
    auto it = byId.find(id);
    return it == byId.end() ? nullptr : it->second;
}

std::vector<std::string> RojoTree::luauSourceFiles() const
{
    std::set<std::string> result;
    for (const auto& node : nodes)
        if (node->isLuau())
            result.insert(node->sourcePath);
    return std::vector<std::string>(result.begin(), result.end());
}

std::string RojoTree::normalizePath(const std::string& path) const
{
    std::string abs = fs::absolute(path).lexically_normal().string();
    auto it = absoluteToId.find(abs);
    if (it != absoluteToId.end())
        return it->second;
    return path;
}

} // namespace astra
