// astra-analyze - statischer Luau-Typecheck eines Rojo-Projekts gegen die Roblox-API-Definitionen.
//
// Teile dieser Datei (ConfigResolver, TaskScheduler, Grundgeruest von main) sind abgeleitet von
// Luau CLI/src/Analyze.cpp:
//
//   MIT License
//   Copyright (c) 2019-2025 Roblox Corporation
//   Copyright (c) 1994-2019 Lua.org, PUC-Rio.
//
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
//   associated documentation files (the "Software"), to deal in the Software without restriction,
//   including without limitation the rights to use, copy, modify, merge, publish, distribute,
//   sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
//   furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all copies or
//   substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
//   NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//   DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
//   OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#include "Luau/Ast.h"
#include "Luau/BuiltinDefinitions.h"
#include "Luau/Config.h"
#include "Luau/Error.h"
#include "Luau/Frontend.h"
#include "Luau/LuauConfig.h"
#include "Luau/ModuleResolver.h"
#include "Luau/StringUtils.h"
#include "Luau/TimeTrace.h"
#include "Luau/ToString.h"
#include "Luau/TypeCheckLimits.h"

#include "Luau/FileUtils.h"
#include "lua.h"
#include "Luau/Flags.h"

#include "RobloxMagic.h"
#include "RojoTree.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <functional>
#include <mutex>
#include <queue>
#include <set>
#include <thread>
#include <unordered_set>
#include <utility>

#include <stdio.h>
#include <string.h>

LUAU_FASTFLAG(LuauSolverV2)
LUAU_FASTINT(LuauTarjanChildLimit)

namespace fs = std::filesystem;

static const char* kVersion = "astra-analyze 0.1.0";

// Reihenfolge exakt wie Luau::TypeErrorData; wird von CMake aus Analysis/include/Luau/Error.h erzeugt.
static const char* kTypeErrorNames[] = {
#include "TypeErrorNames.inc"
};

static const char* typeErrorName(const Luau::TypeError& error)
{
    int index = error.data.index();
    if (index >= 0 && size_t(index) < sizeof(kTypeErrorNames) / sizeof(kTypeErrorNames[0]))
        return kTypeErrorNames[index];
    return "TypeError";
}

// ---------------------------------------------------------------------------------------------
// Diagnosen sammeln & ausgeben
// ---------------------------------------------------------------------------------------------

struct Diagnostic
{
    std::string file;
    Luau::Location location;
    std::string severity; // "error" | "warning"
    std::string code;
    std::string message;
};

static std::string singleLine(const std::string& message)
{
    std::string out;
    out.reserve(message.size());
    for (size_t i = 0; i < message.size(); ++i)
    {
        char c = message[i];
        if (c == '\n')
        {
            while (!out.empty() && out.back() == ' ')
                out.pop_back();
            size_t j = i + 1;
            while (j < message.size() && (message[j] == ' ' || message[j] == '\t'))
                ++j;
            if (j < message.size())
                out += "; ";
            i = j - 1;
        }
        else
            out += c;
    }
    return out;
}

static std::string jsonEscape(const std::string& s)
{
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char c : s)
    {
        switch (c)
        {
        case '"':
            out += "\\\"";
            break;
        case '\\':
            out += "\\\\";
            break;
        case '\n':
            out += "\\n";
            break;
        case '\r':
            out += "\\r";
            break;
        case '\t':
            out += "\\t";
            break;
        default:
            if (c < 0x20)
            {
                char buf[8];
                snprintf(buf, sizeof(buf), "\\u%04x", c);
                out += buf;
            }
            else
                out += char(c);
        }
    }
    return out;
}

// ---------------------------------------------------------------------------------------------
// FileResolver: liest Quellen und loest require(script...) ueber den Rojo-Baum auf
// ---------------------------------------------------------------------------------------------

static const char kMissingPrefix[] = "\x01missing\x01";

static bool isMissingId(const std::string& name)
{
    return name.rfind(kMissingPrefix, 0) == 0;
}

struct RojoFileResolver : Luau::FileResolver
{
    explicit RojoFileResolver(const astra::RojoTree& tree, bool forceStrict)
        : tree(tree)
        , forceStrict(forceStrict)
    {
    }

    const astra::RojoTree& tree;
    bool forceStrict;

    std::optional<Luau::SourceCode> readSource(const Luau::ModuleName& name) override
    {
        if (isMissingId(name))
            return std::nullopt;

        Luau::SourceCode::Type type = Luau::SourceCode::Module;
        std::string path = name;

        if (const astra::RojoNode* node = tree.findById(name))
        {
            if (node->kind == astra::NodeKind::DataModule)
                return Luau::SourceCode{"-- generated by astra-analyze: data module (JSON/TOML) is typed as any\nreturn (nil :: any)\n", Luau::SourceCode::Module};
            if (!node->isLuau())
                return std::nullopt;
            path = node->sourcePath;
            type = node->kind == astra::NodeKind::ModuleScript ? Luau::SourceCode::Module : Luau::SourceCode::Script;
        }

        std::optional<std::string> source = readFile(path);
        if (!source)
            return std::nullopt;

        if (forceStrict)
            forceStrictHotComments(*source);

        return Luau::SourceCode{std::move(*source), type};
    }

    static void replaceAll(std::string& s, const std::string& from, const std::string& to)
    {
        size_t pos = 0;
        while ((pos = s.find(from, pos)) != std::string::npos)
        {
            s.replace(pos, from.size(), to);
            pos += to.size();
        }
    }

    // Ersetzt Mode-Hot-Comments durch --!strict, Laenge bleibt gleich (Spalten bleiben korrekt).
    static void forceStrictHotComments(std::string& source)
    {
        replaceAll(source, "--!nonstrict", "--!strict   ");
        replaceAll(source, "--!nocheck", "--!strict ");
    }

    std::optional<Luau::ModuleInfo> navigate(const std::string& contextName, const std::string& key)
    {
        const astra::RojoNode* node = tree.findById(contextName);
        if (!node)
        {
            if (isMissingId(contextName) && key != "Parent")
                return Luau::ModuleInfo{contextName + "." + key};
            return std::nullopt;
        }

        if (key == "Parent")
        {
            if (node->parent)
                return Luau::ModuleInfo{node->parent->id};
            return std::nullopt; // verlaesst --root
        }

        auto it = node->children.find(key);
        if (it != node->children.end())
            return Luau::ModuleInfo{it->second->id};

        return Luau::ModuleInfo{std::string(kMissingPrefix) + node->id + "\x01" + key};
    }

    std::optional<Luau::ModuleInfo> resolveModule(const Luau::ModuleInfo* context, Luau::AstExpr* expr, const Luau::TypeCheckLimits& limits) override
    {
        if (!context)
            return std::nullopt;

        if (Luau::AstExprGlobal* global = expr->as<Luau::AstExprGlobal>())
        {
            if (global->name == "script")
            {
                if (const astra::RojoNode* node = tree.findById(context->name))
                    return Luau::ModuleInfo{node->id};
            }
            return std::nullopt;
        }

        if (Luau::AstExprIndexName* index = expr->as<Luau::AstExprIndexName>())
            return navigate(context->name, std::string(index->index.value));

        // script.Parent["Name mit Leerzeichen"]
        if (Luau::AstExprIndexExpr* index = expr->as<Luau::AstExprIndexExpr>())
        {
            if (Luau::AstExprConstantString* str = index->index->as<Luau::AstExprConstantString>())
                return navigate(context->name, std::string(str->value.data, str->value.size));
            return std::nullopt;
        }

        // script.Parent:WaitForChild("X") / :FindFirstChild("X")
        if (Luau::AstExprCall* call = expr->as<Luau::AstExprCall>(); call && call->self)
        {
            Luau::AstExprIndexName* fn = call->func->as<Luau::AstExprIndexName>();
            if (!fn || call->args.size < 1)
                return std::nullopt;
            std::string method(fn->index.value);
            Luau::AstExprConstantString* str = call->args.data[0]->as<Luau::AstExprConstantString>();
            if (!str)
                return std::nullopt;
            std::string childName(str->value.data, str->value.size);
            if (method == "WaitForChild" || method == "FindFirstChild")
            {
                if (childName == "Parent") // Kindsuche, nicht Property
                {
                    const astra::RojoNode* node = tree.findById(context->name);
                    if (node && node->children.count("Parent"))
                        return Luau::ModuleInfo{node->children.at("Parent")->id};
                    return std::nullopt;
                }
                return navigate(context->name, childName);
            }
        }

        return std::nullopt;
    }

    std::string getHumanReadableModuleName(const Luau::ModuleName& name) const override
    {
        if (isMissingId(name))
        {
            std::string rest = name.substr(sizeof(kMissingPrefix) - 1);
            size_t sep = rest.find('\x01');
            std::string base = rest.substr(0, sep);
            std::string child = sep == std::string::npos ? "" : rest.substr(sep + 1);
            size_t dot = child.find('.');
            std::string first = child.substr(0, dot);
            std::string baseDisplay = base;
            if (const astra::RojoNode* baseNode = tree.findById(base))
                baseDisplay = std::string(baseNode->className()) + " '" + baseNode->name + "' (" + base + ")";
            std::string msg = "'" + first + "' is not a child of " + baseDisplay + " in the Rojo tree";
            if (dot != std::string::npos)
                msg += " (while resolving '" + child + "')";
            return msg;
        }

        if (const astra::RojoNode* node = tree.findById(name))
        {
            switch (node->kind)
            {
            case astra::NodeKind::Folder:
                return name + " (Folder, not a ModuleScript)";
            case astra::NodeKind::Other:
                return name + " (non-script instance, not a ModuleScript)";
            default:
                break;
            }
        }
        return name;
    }
};

// ---------------------------------------------------------------------------------------------
// ConfigResolver (.luaurc / .config.luau), aus Analyze.cpp uebernommen
// ---------------------------------------------------------------------------------------------

struct LuauConfigInterruptInfo
{
    Luau::TypeCheckLimits limits;
    std::string module;
};

struct CliConfigResolver : Luau::ConfigResolver
{
    Luau::Config defaultConfig;
    std::optional<Luau::Mode> forcedMode;

    mutable std::mutex mutex;
    mutable std::unordered_map<std::string, Luau::Config> configCache;
    mutable std::vector<std::pair<std::string, std::string>> configErrors;

    CliConfigResolver(Luau::Mode mode, std::optional<Luau::Mode> forcedMode)
        : forcedMode(forcedMode)
    {
        defaultConfig.mode = mode;
    }

    const Luau::Config& getConfig(const Luau::ModuleName& name, const Luau::TypeCheckLimits& limits) const override
    {
        std::lock_guard<std::mutex> guard(mutex);
        std::optional<std::string> path = getParentPath(name);
        if (!path || name.empty() || name[0] == '\x01')
            return defaultConfig;

        return readConfigRec(*path, limits);
    }

    const Luau::Config& readConfigRec(const std::string& path, const Luau::TypeCheckLimits& limits) const
    {
        auto it = configCache.find(path);
        if (it != configCache.end())
            return it->second;

        std::optional<std::string> parent = getParentPath(path);
        Luau::Config result = parent ? readConfigRec(*parent, limits) : defaultConfig;

        std::optional<std::string> configPath = joinPaths(path, Luau::kConfigName);
        if (!isFile(*configPath))
            configPath = std::nullopt;

        std::optional<std::string> luauConfigPath = joinPaths(path, Luau::kLuauConfigName);
        if (!isFile(*luauConfigPath))
            luauConfigPath = std::nullopt;

        if (configPath && luauConfigPath)
        {
            std::string ambiguousError = Luau::format("Both %s and %s files exist", Luau::kConfigName, Luau::kLuauConfigName);
            configErrors.emplace_back(*configPath, std::move(ambiguousError));
        }
        else if (configPath)
        {
            if (std::optional<std::string> contents = readFile(*configPath))
            {
                Luau::ConfigOptions::AliasOptions aliasOpts;
                aliasOpts.configLocation = *configPath;
                aliasOpts.overwriteAliases = true;

                Luau::ConfigOptions opts;
                opts.aliasOptions = std::move(aliasOpts);

                std::optional<std::string> error = Luau::parseConfig(*contents, result, opts);
                if (error)
                    configErrors.emplace_back(*configPath, *error);
            }
        }
        else if (luauConfigPath)
        {
            if (std::optional<std::string> contents = readFile(*luauConfigPath))
            {
                Luau::ConfigOptions::AliasOptions aliasOpts;
                aliasOpts.configLocation = *luauConfigPath;
                aliasOpts.overwriteAliases = true;

                Luau::InterruptCallbacks callbacks;
                LuauConfigInterruptInfo info{limits, *luauConfigPath};
                callbacks.initCallback = [&info](lua_State* L)
                {
                    lua_setthreaddata(L, &info);
                };
                callbacks.interruptCallback = [](lua_State* L, int gc)
                {
                    LuauConfigInterruptInfo* info = static_cast<LuauConfigInterruptInfo*>(lua_getthreaddata(L));
                    if (info->limits.finishTime && Luau::TimeTrace::getClock() > *info->limits.finishTime)
                        throw Luau::TimeLimitError{info->module};
                    if (info->limits.cancellationToken && info->limits.cancellationToken->requested())
                        throw Luau::UserCancelError{info->module};
                };

                std::optional<std::string> error = Luau::extractLuauConfig(*contents, result, aliasOpts, std::move(callbacks));
                if (error)
                    configErrors.emplace_back(*luauConfigPath, *error);
            }
        }

        if (forcedMode)
            result.mode = *forcedMode;

        return configCache[path] = result;
    }
};

// ---------------------------------------------------------------------------------------------
// TaskScheduler, aus Analyze.cpp uebernommen
// ---------------------------------------------------------------------------------------------

struct TaskScheduler
{
    TaskScheduler(unsigned threadCount)
        : threadCount(threadCount)
    {
        for (unsigned i = 0; i < threadCount; i++)
        {
            workers.emplace_back(
                [this]
                {
                    workerFunction();
                }
            );
        }
    }

    ~TaskScheduler()
    {
        for (unsigned i = 0; i < threadCount; i++)
            push({});

        for (std::thread& worker : workers)
            worker.join();
    }

    std::function<void()> pop()
    {
        std::unique_lock guard(mtx);

        cv.wait(
            guard,
            [this]
            {
                return !tasks.empty();
            }
        );

        std::function<void()> task = tasks.front();
        tasks.pop();
        return task;
    }

    void push(std::function<void()> task)
    {
        {
            std::unique_lock guard(mtx);
            tasks.push(std::move(task));
        }

        cv.notify_one();
    }

    static unsigned getThreadCount()
    {
        return std::max(std::thread::hardware_concurrency(), 1u);
    }

private:
    void workerFunction()
    {
        while (std::function<void()> task = pop())
            task();
    }

    unsigned threadCount = 1;
    std::mutex mtx;
    std::condition_variable cv;
    std::vector<std::thread> workers;
    std::queue<std::function<void()>> tasks;
};

// ---------------------------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------------------------

static void displayHelp(const char* argv0)
{
    printf("%s\n\n", kVersion);
    printf("Usage: %s --defs <globalTypes.d.luau> --root <rojoSrcDir> [options] [paths...]\n", argv0);
    printf("\n");
    printf("Type-checks Luau files of a Rojo project against Roblox API definitions (luau-lsp format).\n");
    printf("paths: files or directories (default: all .luau/.lua files under --root)\n");
    printf("\n");
    printf("Options:\n");
    printf("  --defs <file>          Roblox definitions file (required), may be given multiple times\n");
    printf("  --root <dir>           Rojo source directory used to resolve require(script...) (required)\n");
    printf("  --json                 machine readable JSON output on stdout\n");
    printf("  --strict               default mode strict for files without --!strict/--!nonstrict\n");
    printf("  --force-strict         check every file in strict mode (overrides --!nonstrict/--!nocheck)\n");
    printf("  --mode=strict|nonstrict  same as --strict / default (nonstrict)\n");
    printf("  --solver=old|new       Luau type solver (default: old)\n");
    printf("  --no-lint              disable lint warnings\n");
    printf("  --warnings-as-errors   exit code 1 also when only lint warnings are present\n");
    printf("  --script-typed         keep `script` typed as in the definitions (default: any)\n");
    printf("  --no-datamodel-services  do not add game.Players/game.ReplicatedStorage/... shortcuts\n");
    printf("  --fflags=<list>        set Luau fast flags (Name=true,Name2=false)\n");
    printf("  -j<N>                  number of worker threads (default: min(cores, 8))\n");
    printf("  --quiet                no summary line on stderr\n");
    printf("  --dump-tree            print the Rojo instance tree and exit\n");
    printf("  --version, --help\n");
    printf("\n");
    printf("Exit code: 0 = no errors, 1 = type/syntax errors found, 2 = usage or definition-file error\n");
}

static int assertionHandler(const char* expr, const char* file, int line, const char* function)
{
    fprintf(stderr, "%s(%d): ASSERTION FAILED: %s\n", file, line, expr);
    fflush(stderr);
    return 1;
}

static bool isLuauSourceFile(const std::string& path)
{
    auto endsWith = [&](const char* suffix)
    {
        size_t n = strlen(suffix);
        return path.size() >= n && path.compare(path.size() - n, n, suffix) == 0;
    };
    return endsWith(".luau") || endsWith(".lua");
}

static void collectFiles(const std::string& path, std::vector<std::string>& out)
{
    std::error_code ec;
    if (fs::is_directory(path, ec))
    {
        std::vector<std::string> found;
        for (fs::recursive_directory_iterator it(path, fs::directory_options::skip_permission_denied, ec), end; !ec && it != end; it.increment(ec))
        {
            std::string name = it->path().filename().string();
            if (!name.empty() && name[0] == '.')
            {
                if (it->is_directory(ec))
                    it.disable_recursion_pending();
                continue;
            }
            if (it->is_regular_file(ec) && isLuauSourceFile(name))
                found.push_back(it->path().string());
        }
        std::sort(found.begin(), found.end());
        out.insert(out.end(), found.begin(), found.end());
    }
    else
        out.push_back(path);
}

// Erlaubt zusaetzlich Integer-Flags (Name=123), die setLuauFlags aus der Luau-CLI nicht kennt.
static void setFlagList(const char* list)
{
    std::string rest = list;
    std::string boolFlags;
    size_t start = 0;
    while (start <= rest.size())
    {
        size_t end = rest.find(',', start);
        std::string element = rest.substr(start, end == std::string::npos ? std::string::npos : end - start);
        size_t eq = element.find('=');
        bool handled = false;
        if (eq != std::string::npos)
        {
            std::string key = element.substr(0, eq);
            std::string value = element.substr(eq + 1);
            char* parseEnd = nullptr;
            long v = strtol(value.c_str(), &parseEnd, 10);
            if (!value.empty() && parseEnd && *parseEnd == 0)
            {
                for (Luau::FValue<int>* flag = Luau::FValue<int>::list; flag; flag = flag->next)
                {
                    if (key == flag->name)
                    {
                        flag->value = int(v);
                        handled = true;
                        break;
                    }
                }
                if (!handled)
                {
                    fprintf(stderr, "Warning: unrecognized integer flag '%s'.\n", key.c_str());
                    handled = true;
                }
            }
        }
        if (!handled && !element.empty())
            boolFlags += (boolFlags.empty() ? "" : ",") + element;
        if (end == std::string::npos)
            break;
        start = end + 1;
    }
    if (!boolFlags.empty())
        setLuauFlags(boolFlags.c_str());
}

static void dumpTree(const astra::RojoNode* node, int depth)
{
    printf("%*s%s [%s] %s\n", depth * 2, "", node->name.c_str(), node->className(), node->id.c_str());
    for (const auto& [_, child] : node->children)
        dumpTree(child, depth + 1);
}

int main(int argc, char** argv)
{
    Luau::assertHandler() = assertionHandler;

    setLuauFlagsDefault();

    std::vector<std::string> defsFiles;
    std::string rootDir;
    std::vector<std::string> inputPaths;
    bool json = false;
    bool runLint = true;
    bool warningsAsErrors = false;
    bool quiet = false;
    bool dumpTreeAndExit = false;
    bool newSolver = false;
    Luau::Mode mode = Luau::Mode::Nonstrict;
    bool forceStrict = false;
    int threadCount = 0;
    astra::ExtensionOptions extOptions;

    auto takeValue = [&](int& i, const char* opt) -> std::string
    {
        size_t n = strlen(opt);
        if (argv[i][n] == '=')
            return std::string(argv[i] + n + 1);
        if (i + 1 >= argc)
        {
            fprintf(stderr, "error: %s needs a value\n", opt);
            exit(2);
        }
        return std::string(argv[++i]);
    };

    auto isOpt = [&](int i, const char* opt)
    {
        size_t n = strlen(opt);
        return strncmp(argv[i], opt, n) == 0 && (argv[i][n] == 0 || argv[i][n] == '=');
    };

    for (int i = 1; i < argc; ++i)
    {
        const char* a = argv[i];
        if (a[0] != '-' || strcmp(a, "-") == 0)
        {
            inputPaths.push_back(a);
            continue;
        }

        if (strcmp(a, "--help") == 0 || strcmp(a, "-h") == 0)
        {
            displayHelp(argv[0]);
            return 0;
        }
        else if (strcmp(a, "--version") == 0)
        {
            printf("%s\n", kVersion);
            return 0;
        }
        else if (isOpt(i, "--defs"))
            defsFiles.push_back(takeValue(i, "--defs"));
        else if (isOpt(i, "--root"))
            rootDir = takeValue(i, "--root");
        else if (strcmp(a, "--json") == 0)
            json = true;
        else if (strcmp(a, "--strict") == 0 || strcmp(a, "--mode=strict") == 0)
            mode = Luau::Mode::Strict;
        else if (strcmp(a, "--mode=nonstrict") == 0)
            mode = Luau::Mode::Nonstrict;
        else if (strcmp(a, "--force-strict") == 0)
        {
            forceStrict = true;
            mode = Luau::Mode::Strict;
        }
        else if (strcmp(a, "--solver=new") == 0)
            newSolver = true;
        else if (strcmp(a, "--solver=old") == 0)
            newSolver = false;
        else if (strcmp(a, "--no-lint") == 0)
            runLint = false;
        else if (strcmp(a, "--warnings-as-errors") == 0)
            warningsAsErrors = true;
        else if (strcmp(a, "--script-typed") == 0)
            extOptions.scriptIsAny = false;
        else if (strcmp(a, "--no-datamodel-services") == 0)
            extOptions.dataModelServices = false;
        else if (strcmp(a, "--quiet") == 0)
            quiet = true;
        else if (strcmp(a, "--dump-tree") == 0)
            dumpTreeAndExit = true;
        else if (strncmp(a, "--fflags=", 9) == 0)
            setFlagList(a + 9);
        else if (strncmp(a, "-j", 2) == 0)
            threadCount = int(strtol(a + 2, nullptr, 10));
        else
        {
            fprintf(stderr, "error: unknown option '%s' (see --help)\n", a);
            return 2;
        }
    }

    if (rootDir.empty())
    {
        fprintf(stderr, "error: --root <dir> is required (see --help)\n");
        return 2;
    }

    astra::RojoTree tree;
    {
        std::string error;
        if (!tree.build(rootDir, error))
        {
            fprintf(stderr, "error: %s\n", error.c_str());
            return 2;
        }
    }

    if (dumpTreeAndExit)
    {
        dumpTree(tree.root(), 0);
        for (const std::string& w : tree.warnings)
            fprintf(stderr, "warning: %s\n", w.c_str());
        return 0;
    }

    if (defsFiles.empty())
    {
        fprintf(stderr, "error: --defs <file> is required (see --help)\n");
        return 2;
    }

    FFlag::LuauSolverV2.value = newSolver;

    auto startTime = std::chrono::steady_clock::now();

    Luau::FrontendOptions frontendOptions;
    frontendOptions.retainFullTypeGraphs = false;
    frontendOptions.runLintChecks = runLint;

    RojoFileResolver fileResolver(tree, forceStrict);
    CliConfigResolver configResolver(mode, forceStrict ? std::optional<Luau::Mode>(Luau::Mode::Strict) : std::nullopt);
    Luau::Frontend frontend(newSolver ? Luau::SolverMode::New : Luau::SolverMode::Old, &fileResolver, &configResolver, frontendOptions);

    Luau::registerBuiltinGlobals(frontend, frontend.globals);

    std::vector<std::string> extWarnings;
    for (const std::string& defsFile : defsFiles)
    {
        std::optional<std::string> defsSource = readFile(defsFile);
        if (!defsSource)
        {
            fprintf(stderr, "error: cannot read definitions file %s\n", defsFile.c_str());
            return 2;
        }

        // Die Roblox-Definitionen bilden einen sehr grossen Typgraphen; das Klonen der oeffentlichen
        // Schnittstelle wuerde am Standard-Tarjan-Limit (10000) scheitern ("Code is too complex").
        // Waehrend des Ladens wird das Limit deshalb aufgehoben und danach wiederhergestellt.
        int savedTarjanLimit = FInt::LuauTarjanChildLimit.value;
        FInt::LuauTarjanChildLimit.value = 0;
        Luau::LoadDefinitionFileResult loadResult =
            frontend.loadDefinitionFile(frontend.globals, frontend.globals.globalScope, *defsSource, "@roblox", /* captureComments */ false, false);
        FInt::LuauTarjanChildLimit.value = savedTarjanLimit;

        if (!loadResult.success)
        {
            size_t shown = 0;
            for (const Luau::ParseError& e : loadResult.parseResult.errors)
            {
                if (shown++ < 50)
                    fprintf(
                        stderr,
                        "%s:%d:%d: error: %s\n",
                        defsFile.c_str(),
                        e.getLocation().begin.line + 1,
                        e.getLocation().begin.column + 1,
                        e.getMessage().c_str()
                    );
            }
            if (loadResult.module)
            {
                for (const Luau::TypeError& e : loadResult.module->errors)
                {
                    if (shown++ < 50)
                        fprintf(
                            stderr,
                            "%s:%d:%d: error: %s\n",
                            defsFile.c_str(),
                            e.location.begin.line + 1,
                            e.location.begin.column + 1,
                            singleLine(Luau::toString(e)).c_str()
                        );
                }
            }
            fprintf(stderr, "error: failed to load definitions file %s (%zu problems)\n", defsFile.c_str(), shown);
            return 2;
        }

        astra::RobloxMetadata metadata = astra::parseMetadata(*defsSource);
        if (defsFile == defsFiles.front())
            astra::installRobloxExtensions(frontend, frontend.globals, metadata, extOptions, extWarnings);
    }

    Luau::freeze(frontend.globals.globalTypes);

    auto defsLoadedTime = std::chrono::steady_clock::now();

    for (const std::string& w : tree.warnings)
        fprintf(stderr, "astra-analyze: warning: %s\n", w.c_str());
    for (const std::string& w : extWarnings)
        fprintf(stderr, "astra-analyze: warning: %s\n", w.c_str());

    // Eingabedateien bestimmen
    std::vector<std::string> files;
    if (inputPaths.empty())
        files = tree.luauSourceFiles();
    else
    {
        std::vector<std::string> raw;
        for (const std::string& p : inputPaths)
            collectFiles(p, raw);
        std::set<std::string> seen;
        for (const std::string& p : raw)
        {
            std::string n = tree.normalizePath(p);
            if (seen.insert(n).second)
                files.push_back(n);
        }
    }

    for (const std::string& name : files)
        frontend.queueModuleCheck(name);

    if (threadCount <= 0)
        threadCount = int(std::min(TaskScheduler::getThreadCount(), 8u));

    std::vector<Diagnostic> diagnostics;
    bool internalError = false;

    try
    {
        TaskScheduler scheduler(threadCount);

        frontend.checkQueuedModules(
            std::nullopt,
            [&](std::vector<std::function<void()>> tasks)
            {
                for (auto& task : tasks)
                    scheduler.push(std::move(task));
            }
        );
    }
    catch (const Luau::InternalCompilerError& ice)
    {
        Luau::Location location = ice.location ? *ice.location : Luau::Location();
        std::string moduleName = ice.moduleName ? *ice.moduleName : "<unknown module>";
        diagnostics.push_back({fileResolver.getHumanReadableModuleName(moduleName), location, "error", "InternalCompilerError", ice.message});
        internalError = true;
    }

    size_t errorCount = 0;
    size_t warningCount = 0;

    if (!internalError)
    {
        for (const std::string& name : files)
        {
            std::optional<Luau::CheckResult> cr = frontend.getCheckResult(name, false);
            if (!cr || !frontend.getSourceModule(name))
            {
                diagnostics.push_back({name, Luau::Location(), "error", "FileError", "cannot open or check file"});
                continue;
            }

            std::string humanName = fileResolver.getHumanReadableModuleName(name);

            for (const Luau::TypeError& error : cr->errors)
            {
                Diagnostic d;
                d.file = fileResolver.getHumanReadableModuleName(error.moduleName);
                d.location = error.location;
                d.severity = "error";
                if (const Luau::SyntaxError* syntaxError = Luau::get_if<Luau::SyntaxError>(&error.data))
                {
                    d.code = "SyntaxError";
                    d.message = syntaxError->message;
                }
                else
                {
                    d.code = typeErrorName(error);
                    d.message = singleLine(Luau::toString(error, Luau::TypeErrorToStringOptions{frontend.fileResolver})) + astra::suggestionForError(error);
                }
                diagnostics.push_back(std::move(d));
            }

            for (const Luau::LintWarning& w : cr->lintResult.errors)
                diagnostics.push_back({humanName, w.location, "error", Luau::LintWarning::getName(w.code), singleLine(w.text)});
            for (const Luau::LintWarning& w : cr->lintResult.warnings)
                diagnostics.push_back({humanName, w.location, "warning", Luau::LintWarning::getName(w.code), singleLine(w.text)});
        }
    }

    for (const auto& [path, message] : configResolver.configErrors)
        diagnostics.push_back({path, Luau::Location(), "error", "ConfigError", message});

    std::stable_sort(
        diagnostics.begin(),
        diagnostics.end(),
        [](const Diagnostic& a, const Diagnostic& b)
        {
            if (a.file != b.file)
                return a.file < b.file;
            if (a.location.begin.line != b.location.begin.line)
                return a.location.begin.line < b.location.begin.line;
            return a.location.begin.column < b.location.begin.column;
        }
    );

    for (const Diagnostic& d : diagnostics)
        (d.severity == "error" ? errorCount : warningCount)++;

    auto endTime = std::chrono::steady_clock::now();
    double totalSeconds = std::chrono::duration<double>(endTime - startTime).count();
    double defsSeconds = std::chrono::duration<double>(defsLoadedTime - startTime).count();

    if (json)
    {
        printf("{\n  \"diagnostics\": [");
        for (size_t i = 0; i < diagnostics.size(); ++i)
        {
            const Diagnostic& d = diagnostics[i];
            printf(
                "%s\n    {\"file\": \"%s\", \"line\": %u, \"column\": %u, \"endLine\": %u, \"endColumn\": %u, \"severity\": \"%s\", \"code\": \"%s\", "
                "\"message\": \"%s\"}",
                i ? "," : "",
                jsonEscape(d.file).c_str(),
                d.location.begin.line + 1,
                d.location.begin.column + 1,
                d.location.end.line + 1,
                d.location.end.column + 1,
                d.severity.c_str(),
                jsonEscape(d.code).c_str(),
                jsonEscape(d.message).c_str()
            );
        }
        printf(
            "%s],\n  \"summary\": {\"files\": %zu, \"errors\": %zu, \"warnings\": %zu, \"seconds\": %.3f, \"solver\": \"%s\"}\n}\n",
            diagnostics.empty() ? "" : "\n  ",
            files.size(),
            errorCount,
            warningCount,
            totalSeconds,
            newSolver ? "new" : "old"
        );
    }
    else
    {
        for (const Diagnostic& d : diagnostics)
            printf(
                "%s:%u:%u: %s: %s [%s]\n",
                d.file.c_str(),
                d.location.begin.line + 1,
                d.location.begin.column + 1,
                d.severity.c_str(),
                d.message.c_str(),
                d.code.c_str()
            );
    }
    fflush(stdout);

    if (!quiet)
        fprintf(
            stderr,
            "astra-analyze: %zu files checked, %zu errors, %zu warnings (%.2fs, definitions %.2fs, %s solver)\n",
            files.size(),
            errorCount,
            warningCount,
            totalSeconds,
            defsSeconds,
            newSolver ? "new" : "old"
        );

    if (errorCount > 0 || (warningsAsErrors && warningCount > 0))
        return 1;
    return 0;
}
