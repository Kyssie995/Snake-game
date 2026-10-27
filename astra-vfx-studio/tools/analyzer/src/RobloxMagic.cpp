// astra-analyze - Roblox-spezifische Erweiterungen der globalen Typumgebung
// SPDX-License-Identifier: MIT
//
// Die luau-lsp-Definitionsdatei deklariert z.B. `Instance.new(className: string): Instance` und
// `GetService(self, className: string): Instance`. luau-lsp selbst haengt zur Laufzeit "magische"
// Funktionen an diese Typen, damit `Instance.new("Part")` den Typ `Part` liefert. Genau das wird hier
// nachgebaut (fuer den alten Solver ueber handleOldSolver, fuer den neuen Solver ueber infer/refine).

#include "RobloxMagic.h"

#include "Luau/Ast.h"
#include "Luau/BuiltinDefinitions.h"
#include "Luau/ConstraintSolver.h"
#include "Luau/Error.h"
#include "Luau/Frontend.h"
#include "Luau/GlobalTypes.h"
#include "Luau/LValue.h"
#include "Luau/Predicate.h"
#include "Luau/Scope.h"
#include "Luau/Type.h"
#include "Luau/TypeInfer.h"
#include "Luau/TypePack.h"

#include <algorithm>
#include <cctype>
#include <memory>
#include <optional>

namespace astra
{

using namespace Luau;

// ---------------------------------------------------------------------------------------------
// Metadaten
// ---------------------------------------------------------------------------------------------

static void parseStringArray(const std::string& line, const std::string& key, std::unordered_set<std::string>& out)
{
    size_t pos = line.find("\"" + key + "\"");
    if (pos == std::string::npos)
        return;
    size_t open = line.find('[', pos);
    size_t close = line.find(']', open);
    if (open == std::string::npos || close == std::string::npos)
        return;

    size_t i = open + 1;
    while (i < close)
    {
        size_t q1 = line.find('"', i);
        if (q1 == std::string::npos || q1 >= close)
            break;
        size_t q2 = line.find('"', q1 + 1);
        if (q2 == std::string::npos || q2 > close)
            break;
        out.insert(line.substr(q1 + 1, q2 - q1 - 1));
        i = q2 + 1;
    }
}

RobloxMetadata parseMetadata(const std::string& source)
{
    RobloxMetadata md;
    const std::string marker = "--#METADATA#";
    size_t pos = source.find(marker);
    if (pos == std::string::npos)
        return md;
    size_t eol = source.find('\n', pos);
    std::string line = source.substr(pos, eol == std::string::npos ? std::string::npos : eol - pos);
    parseStringArray(line, "CREATABLE_INSTANCES", md.creatableInstances);
    parseStringArray(line, "SERVICES", md.services);
    return md;
}

// ---------------------------------------------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------------------------------------------

static std::string toLower(std::string s)
{
    for (char& c : s)
        c = char(std::tolower((unsigned char)c));
    return s;
}

// Damerau-Levenshtein (optimal string alignment): Vertauschungen ("Nmae" -> "Name") zaehlen als 1.
static size_t editDistance(const std::string& a, const std::string& b)
{
    const size_t n = a.size(), m = b.size();
    std::vector<std::vector<size_t>> d(n + 1, std::vector<size_t>(m + 1));
    for (size_t i = 0; i <= n; ++i)
        d[i][0] = i;
    for (size_t j = 0; j <= m; ++j)
        d[0][j] = j;
    for (size_t i = 1; i <= n; ++i)
    {
        for (size_t j = 1; j <= m; ++j)
        {
            size_t cost = a[i - 1] == b[j - 1] ? 0 : 1;
            d[i][j] = std::min({d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost});
            if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1])
                d[i][j] = std::min(d[i][j], d[i - 2][j - 2] + 1);
        }
    }
    return d[n][m];
}

template<typename Range>
static std::optional<std::string> closestName(const std::string& wanted, const Range& candidates)
{
    std::string w = toLower(wanted);
    std::optional<std::string> best;
    size_t bestDist = SIZE_MAX;
    for (const std::string& c : candidates)
    {
        if (c == wanted)
            continue;
        size_t d = editDistance(w, toLower(c));
        if (d < bestDist || (d == bestDist && best && c < *best))
        {
            bestDist = d;
            best = c;
        }
    }
    size_t limit = wanted.size() <= 4 ? 1 : (wanted.size() <= 8 ? 2 : 3);
    if (best && bestDist <= limit)
        return best;
    return std::nullopt;
}

static std::string didYouMean(const std::optional<std::string>& s)
{
    return s ? " (did you mean '" + *s + "'?)" : "";
}

static std::optional<std::string> constantString(const AstExpr* e)
{
    if (!e)
        return std::nullopt;
    if (const AstExprConstantString* s = e->as<AstExprConstantString>())
        return std::string(s->value.data, s->value.size);
    return std::nullopt;
}

static const AstExpr* argAt(const AstExprCall& call, size_t index)
{
    return index < call.args.size ? call.args.data[index] : nullptr;
}

static void collectExternProps(TypeId ty, std::vector<std::string>& out)
{
    for (int guard = 0; guard < 100; ++guard)
    {
        const ExternType* et = get<ExternType>(follow(ty));
        if (!et)
            return;
        for (const auto& [name, _] : et->props)
            out.push_back(name);
        if (!et->parent)
            return;
        ty = *et->parent;
    }
}

static bool externHasProp(TypeId ty, const std::string& name)
{
    for (int guard = 0; guard < 100; ++guard)
    {
        const ExternType* et = get<ExternType>(follow(ty));
        if (!et)
            return false;
        if (et->props.count(name))
            return true;
        if (!et->parent)
            return false;
        ty = *et->parent;
    }
    return false;
}

static bool isSubclassOf(TypeId ty, TypeId base)
{
    base = follow(base);
    for (int guard = 0; guard < 100; ++guard)
    {
        ty = follow(ty);
        if (ty == base)
            return true;
        const ExternType* et = get<ExternType>(ty);
        if (!et || !et->parent)
            return false;
        ty = *et->parent;
    }
    return false;
}

// ---------------------------------------------------------------------------------------------
// Gemeinsamer Kontext
// ---------------------------------------------------------------------------------------------

struct RobloxContext
{
    ScopePtr globalScope;
    RobloxMetadata metadata;
    std::vector<std::string> allClassNames; // fuer "did you mean"
    std::optional<TypeId> instanceType;

    std::optional<TypeId> lookupClass(const std::string& name) const
    {
        std::optional<TypeFun> tf = globalScope->lookupType(name);
        if (!tf || !tf->typeParams.empty() || !tf->typePackParams.empty())
            return std::nullopt;
        TypeId ty = follow(tf->type);
        if (!get<ExternType>(ty))
            return std::nullopt;
        return ty;
    }

    // Eine echte Roblox-Klasse (Instance oder Unterklasse), nicht z.B. Vector3 oder EnumItem.
    std::optional<TypeId> lookupInstanceClass(const std::string& name) const
    {
        std::optional<TypeId> ty = lookupClass(name);
        if (!ty)
            return std::nullopt;
        if (instanceType && !isSubclassOf(*ty, *instanceType))
            return std::nullopt;
        return ty;
    }
};

using ContextPtr = std::shared_ptr<RobloxContext>;

enum class MagicKind
{
    InstanceNew,
    GetService,
    FindService,
    IsA,
    FindFirstWhichIsA, // FindFirstChildWhichIsA, FindFirstChildOfClass, FindFirstAncestorWhichIsA, FindFirstAncestorOfClass
    Clone,
    GetPropertyChangedSignal,
};

// Gemeinsame Auswertung fuer beide Solver.
struct MagicOutcome
{
    std::optional<TypeId> resultClass; // Rueckgabetyp (Klasse); bei optional=true als `T?`
    bool optional = false;
    std::optional<TypeId> refineSelfTo; // nur IsA
    std::optional<TypeError> error;
};

struct RobloxMagicFunction final : MagicFunction
{
    RobloxMagicFunction(ContextPtr ctx, MagicKind kind, std::string displayName)
        : ctx(std::move(ctx))
        , kind(kind)
        , displayName(std::move(displayName))
    {
    }

    ContextPtr ctx;
    MagicKind kind;
    std::string displayName;

    bool needsSelf() const
    {
        return kind != MagicKind::InstanceNew;
    }

    MagicOutcome evaluate(const AstExprCall& call, std::optional<TypeId> selfType) const
    {
        MagicOutcome out;

        if (needsSelf() && !call.self)
            return out; // `game.GetService(...)` o.ae. -> normale Pruefung

        const AstExpr* arg0 = argAt(call, 0);
        std::optional<std::string> name = constantString(arg0);
        Location argLoc = arg0 ? arg0->location : call.location;

        switch (kind)
        {
        case MagicKind::InstanceNew:
        {
            if (!name)
                return out;
            std::optional<TypeId> cls = ctx->lookupInstanceClass(*name);
            const auto& creatable = ctx->metadata.creatableInstances;
            if (!cls)
            {
                std::vector<std::string> cands(creatable.begin(), creatable.end());
                if (cands.empty())
                    cands = ctx->allClassNames;
                out.error = TypeError{argLoc, GenericError{"'" + *name + "' is not a valid Roblox class name for Instance.new" + didYouMean(closestName(*name, cands))}};
                return out;
            }
            if (!creatable.empty() && !creatable.count(*name))
                out.error = TypeError{argLoc, GenericError{"'" + *name + "' is not creatable with Instance.new"}};
            out.resultClass = cls;
            return out;
        }
        case MagicKind::GetService:
        case MagicKind::FindService:
        {
            if (!name)
                return out;
            const auto& services = ctx->metadata.services;
            std::optional<TypeId> cls = ctx->lookupInstanceClass(*name);
            if (!cls || (!services.empty() && !services.count(*name)))
            {
                std::vector<std::string> cands(services.begin(), services.end());
                out.error = TypeError{argLoc, GenericError{"'" + *name + "' is not a valid Roblox service name" + didYouMean(closestName(*name, cands))}};
                return out;
            }
            out.resultClass = cls;
            return out;
        }
        case MagicKind::IsA:
        case MagicKind::FindFirstWhichIsA:
        {
            if (!name)
                return out;
            std::optional<TypeId> cls = ctx->lookupInstanceClass(*name);
            if (!cls)
            {
                // IsA wird auch auf Nicht-Instanzen (z.B. Object) aufgerufen; nur bei unbekannten Namen melden
                if (!ctx->lookupClass(*name))
                    out.error = TypeError{
                        argLoc, GenericError{"'" + *name + "' is not a valid Roblox class name for " + displayName + didYouMean(closestName(*name, ctx->allClassNames))}
                    };
                return out;
            }
            if (kind == MagicKind::IsA)
                out.refineSelfTo = cls;
            else
            {
                out.resultClass = cls;
                out.optional = true;
            }
            return out;
        }
        case MagicKind::Clone:
        {
            if (!selfType)
                return out;
            TypeId self = follow(*selfType);
            if (get<ExternType>(self) && (!ctx->instanceType || isSubclassOf(self, *ctx->instanceType)))
                out.resultClass = self;
            return out;
        }
        case MagicKind::GetPropertyChangedSignal:
        {
            if (!name || !selfType)
                return out;
            TypeId self = follow(*selfType);
            if (!get<ExternType>(self))
                return out;
            if (!externHasProp(self, *name))
                out.error = TypeError{argLoc, UnknownProperty{self, *name}};
            return out;
        }
        }
        return out;
    }

    // ----- alter Solver -----
    std::optional<WithPredicate<TypePackId>> handleOldSolver(
        TypeChecker& typechecker,
        const ScopePtr& scope,
        const AstExprCall& expr,
        WithPredicate<TypePackId> withPredicate
    ) override
    {
        auto [paramPack, _predicates] = std::move(withPredicate);
        const auto& [params, tail] = flatten(paramPack);

        std::optional<TypeId> selfType;
        if (expr.self && !params.empty())
            selfType = params[0];

        MagicOutcome outcome = evaluate(expr, selfType);
        if (outcome.error)
            typechecker.reportError(*outcome.error);

        TypeArena& arena = typechecker.currentModule->internalTypes;

        if (kind == MagicKind::IsA && outcome.refineSelfTo && expr.self)
        {
            const AstExprIndexName* index = expr.func->as<AstExprIndexName>();
            std::optional<LValue> lvalue = index ? tryGetLValue(*index->expr) : std::nullopt;
            if (!lvalue)
                return std::nullopt;
            return WithPredicate<TypePackId>{
                arena.addTypePack({typechecker.booleanType}), {IsAPredicate{std::move(*lvalue), expr.location, *outcome.refineSelfTo}}
            };
        }

        if (!outcome.resultClass)
            return std::nullopt; // normale Pruefung gegen die deklarierte Signatur

        // Die normale Argumentpruefung wird bei Magic-Ergebnissen uebersprungen; das optionale
        // Parent-Argument von Instance.new pruefen wir deshalb selbst.
        if (kind == MagicKind::InstanceNew && params.size() >= 2 && ctx->instanceType)
        {
            TypeId optInstance = arena.addType(UnionType{{*ctx->instanceType, typechecker.nilType}});
            ErrorVec errors = typechecker.canUnify(params[1], optInstance, scope, expr.args.size >= 2 ? expr.args.data[1]->location : expr.location);
            if (!errors.empty())
                typechecker.reportError(TypeError{expr.args.size >= 2 ? expr.args.data[1]->location : expr.location, TypeMismatch{optInstance, params[1]}});
        }

        TypeId result = *outcome.resultClass;
        if (outcome.optional)
            result = arena.addType(UnionType{{result, typechecker.nilType}});
        return WithPredicate<TypePackId>{arena.addTypePack({result})};
    }

    // ----- neuer Solver -----
    bool infer(const MagicFunctionCallContext& context) override
    {
        std::optional<TypeId> selfType;
        if (context.callSite->self)
            selfType = first(context.arguments);

        MagicOutcome outcome = evaluate(*context.callSite, selfType);
        if (outcome.error)
            context.solver->reportError(*outcome.error);

        if (!outcome.resultClass)
            return false;

        TypeId result = *outcome.resultClass;
        if (outcome.optional)
            result = context.solver->arena->addType(UnionType{{result, context.solver->builtinTypes->nilType}});

        TypePackId resultPack = context.solver->arena->addTypePack({result});
        asMutable(context.result)->ty.emplace<BoundTypePack>(resultPack);
        return true;
    }

    void refine(const MagicRefinementContext& context) override
    {
        if (kind != MagicKind::IsA || !context.callSite || !context.callSite->self || context.discriminantTypes.empty())
            return;

        std::optional<TypeId> discriminant = context.discriminantTypes[0];
        if (!discriminant)
            return;

        std::optional<std::string> name = constantString(argAt(*context.callSite, 0));
        if (!name)
            return;
        std::optional<TypeId> cls = ctx->lookupInstanceClass(*name);
        if (!cls)
            return;

        TypeId d = follow(*discriminant);
        if (get<BlockedType>(d))
            asMutable(d)->ty.emplace<BoundType>(*cls);
    }
};

// ---------------------------------------------------------------------------------------------
// Installation
// ---------------------------------------------------------------------------------------------

static bool attachTo(std::optional<TypeId> fnTy, std::shared_ptr<MagicFunction> magic)
{
    if (!fnTy)
        return false;
    if (FunctionType* ftv = getMutable<FunctionType>(follow(*fnTy)))
    {
        ftv->magic = std::move(magic);
        return true;
    }
    return false;
}

static std::optional<TypeId> externProp(std::optional<TypeId> cls, const std::string& name)
{
    if (!cls)
        return std::nullopt;
    ExternType* et = getMutable<ExternType>(follow(*cls));
    if (!et)
        return std::nullopt;
    auto it = et->props.find(name);
    if (it == et->props.end())
        return std::nullopt;
    return it->second.readTy;
}

void installRobloxExtensions(
    Frontend& frontend,
    GlobalTypes& globals,
    const RobloxMetadata& metadata,
    const ExtensionOptions& options,
    std::vector<std::string>& warnings
)
{
    auto ctx = std::make_shared<RobloxContext>();
    ctx->globalScope = globals.globalScope;
    ctx->metadata = metadata;
    ctx->instanceType = ctx->lookupClass("Instance");

    for (const auto& [name, tf] : globals.globalScope->exportedTypeBindings)
    {
        if (get<ExternType>(follow(tf.type)) && (!ctx->instanceType || isSubclassOf(tf.type, *ctx->instanceType)))
            ctx->allClassNames.push_back(name);
    }
    std::sort(ctx->allClassNames.begin(), ctx->allClassNames.end());

    if (!ctx->instanceType)
        warnings.push_back("definitions do not declare class 'Instance'; Roblox extensions disabled");

    auto make = [&](MagicKind kind, const std::string& displayName)
    {
        return std::make_shared<RobloxMagicFunction>(ctx, kind, displayName);
    };

    auto require = [&](bool ok, const std::string& what)
    {
        if (!ok)
            warnings.push_back("could not attach type magic to " + what);
    };

    // Instance.new
    {
        bool ok = false;
        TypeId instanceGlobal = getGlobalBinding(globals, "Instance");
        if (TableType* ttv = getMutable<TableType>(follow(instanceGlobal)))
        {
            auto it = ttv->props.find("new");
            if (it != ttv->props.end())
                ok = attachTo(it->second.readTy, make(MagicKind::InstanceNew, "Instance.new"));
        }
        require(ok, "Instance.new");
    }

    std::optional<TypeId> serviceProvider = ctx->lookupClass("ServiceProvider");
    require(attachTo(externProp(serviceProvider, "GetService"), make(MagicKind::GetService, "GetService")), "ServiceProvider:GetService");
    require(attachTo(externProp(serviceProvider, "FindService"), make(MagicKind::FindService, "FindService")), "ServiceProvider:FindService");

    // IsA ist auf Object deklariert (Instance erbt davon)
    {
        std::optional<TypeId> object = ctx->lookupClass("Object");
        bool ok = attachTo(externProp(object, "IsA"), make(MagicKind::IsA, "IsA"));
        if (!ok)
            ok = attachTo(externProp(ctx->instanceType, "IsA"), make(MagicKind::IsA, "IsA"));
        require(ok, "IsA");

        bool ok2 = attachTo(externProp(object, "GetPropertyChangedSignal"), make(MagicKind::GetPropertyChangedSignal, "GetPropertyChangedSignal"));
        if (!ok2)
            ok2 = attachTo(
                externProp(ctx->instanceType, "GetPropertyChangedSignal"), make(MagicKind::GetPropertyChangedSignal, "GetPropertyChangedSignal")
            );
        require(ok2, "GetPropertyChangedSignal");
    }

    for (const char* fn : {"FindFirstChildWhichIsA", "FindFirstChildOfClass", "FindFirstAncestorWhichIsA", "FindFirstAncestorOfClass"})
        require(attachTo(externProp(ctx->instanceType, fn), make(MagicKind::FindFirstWhichIsA, fn)), std::string("Instance:") + fn);

    require(attachTo(externProp(ctx->instanceType, "Clone"), make(MagicKind::Clone, "Clone")), "Instance:Clone");

    // Typ-Namensraum `Enum`: `Enum.Material` als Typannotation -> EnumMaterial (wie in Studio/luau-lsp)
    if (std::optional<TypeId> enumItem = ctx->lookupClass("EnumItem"))
    {
        std::unordered_map<Name, TypeFun> enumTypes;
        for (const auto& [name, tf] : globals.globalScope->exportedTypeBindings)
        {
            if (name.size() <= 4 || name.compare(0, 4, "Enum") != 0)
                continue;
            if (name.size() > 9 && name.compare(name.size() - 9, 9, "_INTERNAL") == 0)
                continue;
            TypeId ty = follow(tf.type);
            if (ty != follow(*enumItem) && get<ExternType>(ty) && isSubclassOf(ty, *enumItem))
                enumTypes[name.substr(4)] = tf;
        }
        if (enumTypes.empty())
            warnings.push_back("no Enum types found in definitions; `Enum.X` type annotations unavailable");
        else if (!globals.globalScope->importedTypeBindings.count("Enum"))
            globals.globalScope->importedTypeBindings["Enum"] = std::move(enumTypes);
    }

    // `script` -> any (Navigation script.Parent.X soll nicht fehlschlagen; requires loest der FileResolver auf)
    if (options.scriptIsAny)
        addGlobalBinding(globals, "script", globals.builtinTypes->anyType, "@astra");

    // game.Players, game.ReplicatedStorage, ... sind zur Laufzeit Kinder des DataModel und per Name erreichbar.
    if (options.dataModelServices)
    {
        static const char* commonServices[] = {
            "Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage",
            "StarterGui", "StarterPack", "StarterPlayer", "Teams", "SoundService", "Chat", "TextChatService", "LocalizationService",
            "TestService", "CoreGui",
        };
        std::optional<TypeId> dataModel = ctx->lookupClass("DataModel");
        if (ExternType* dm = dataModel ? getMutable<ExternType>(follow(*dataModel)) : nullptr)
        {
            for (const char* svc : commonServices)
            {
                if (dm->props.count(svc))
                    continue;
                if (std::optional<TypeId> ty = ctx->lookupInstanceClass(svc))
                    dm->props[svc] = Property::rw(*ty);
            }
        }
    }

    (void)frontend;
}

// ---------------------------------------------------------------------------------------------
// Vorschlaege fuer UnknownProperty
// ---------------------------------------------------------------------------------------------

std::string suggestionForError(const TypeError& error)
{
    const UnknownProperty* up = get_if<UnknownProperty>(&error.data);
    if (!up)
        return "";

    std::vector<std::string> names;
    TypeId ty = follow(up->table);
    if (get<ExternType>(ty))
        collectExternProps(ty, names);
    else if (const TableType* tt = get<TableType>(ty))
    {
        for (const auto& [name, _] : tt->props)
            names.push_back(name);
    }
    else if (const MetatableType* mt = get<MetatableType>(ty))
    {
        if (const TableType* tt2 = get<TableType>(follow(mt->table)))
            for (const auto& [name, _] : tt2->props)
                names.push_back(name);
    }

    return didYouMean(closestName(up->key, names));
}

} // namespace astra
