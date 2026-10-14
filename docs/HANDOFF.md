# Synthèse pour reprise dans une nouvelle session

## Contexte
- Je suis ingénieur Cloud DevSecOps. Sur un compte AWS (ENGIE), deux projets IA tournent déjà :
  - `C:\Users\TZ6429\gitlab\infrastructure-services\applications\trends-analysis` (RAG)
  - `C:\Users\TZ6429\gitlab\infrastructure-services\applications\langgraph-agents` (LangGraph)
- De nouvelles demandes RAG / LangGraph arrivent **sur le même compte**, portées par des **métiers différents**.

## Ce que je demande
1. **Analyser les deux repos existants** (structure Terraform, nommage, tags, packaging Lambda,
   VPC, CI GitLab, appels Bedrock) et réutiliser leurs conventions.
2. **Un schéma d'architecture AWS pour chacun des deux besoins ci-dessous.**
3. **Une façon d'optimiser** : plusieurs demandes de ce type vont arriver → socle mutualisé
   + enveloppe réutilisable par use-case.
4. **Tagger chaque projet pour le chiffrer** (refacturer le coût par métier) ; chiffrement KMS par use-case en complément.
5. Générer les docs **en local** dans `C:\Users\TZ6429\gitlab\infrastructure-services\applications\docs-architecture\`.

## Besoin 1 – `uc01-agents-lab` (prototypage IA)
- Domaines : évaluation de cas d'usage IA et prototypage ; communication entre agents et protocoles ; world models.
- Objectifs : prototypes internes (automatisation du scouting / appels d'offres…), orchestration
  multi-agents (communication, protocoles), explorer les world models, livrer des composants réutilisables.
- Infra : modèles légers Bedrock (Claude Haiku ou équivalent) en MVP ; Lambda pour orchestrer
  LangChain / LangGraph et la communication d'agents ; automatisation serverless des tests et workflows.
- Données : publiques / open source uniquement (HuggingFace, benchmarks) ; plus tard données internes ENGIE sur S3.
- Calcul : modèles existants et petites expérimentations d'abord ; GPU pour entraînement / fine-tuning éventuellement plus tard.

## Besoin 2 – `uc02-hydraulic-schema` (génération de schéma d'ingénierie)
- Objectif : vérifier qu'un LLM peut générer un schéma d'ingénierie simplifié (connexions entre
  équipements, en JSON, puis converti en format CAO) à partir d'une fiche de besoin (puissance,
  fluide, heures de fonctionnement…) et d'un premier jeu de règles métier hydrauliques.
  Ensuite : enrichissement avec l'historique de projets et une base de connaissance.
- Besoins : plusieurs modèles LLM Bedrock (pour comparer) ; environnement Python type SageMaker notebook ;
  S3 (données d'essai puis corpus projets) ; Bedrock Knowledge Bases (RAG) ; base graphe
  Neptune / Neptune Analytics pour représenter les schémas et faire du GraphRAG.

## Déjà produit (session précédente, sans accès aux repos existants)
Repo GitHub `aymane-benchhab/aymane-benchhab`, branche `claude/bold-cannon-bjaad3` :
- `docs/architecture-aws-multi-usecases.md` : socle mutualisé + enveloppe par use-case, architecture
  des 2 besoins, taxonomie de tags, chiffrage mensuel estimé, sécurité, plan.
- `docs/diagrams/*.mmd|png` : 3 schémas (socle, besoin 1, besoin 2).
- `terraform/modules/usecase-baseline/` : tags obligatoires, CMK KMS (ABAC `UseCase`), bucket S3 chiffré,
  rôle IAM workload, Bedrock Application Inference Profiles tagués (coût Bedrock ventilable), AWS Budget.
- `terraform/live/main.tf` : instanciation uc01 + uc02 (`terraform validate` OK, rien déployé).

Choix clés retenus :
- Besoin 1 : Step Functions + agents LangGraph dans Lambda (superviseur, scout, analyste, rédacteur),
  A2A entre agents, MCP pour les outils, DynamoDB checkpointer, évals serverless, SageMaker + Spot pour world models.
- Besoin 2 : pipeline Step Functions (validation fiche → retrieve KB → génération multi-modèles en
  parallèle → contrôle règles en Python déterministe avec boucle de correction max 3 → DXF via ezdxf →
  scoring comparatif) ; phase 1 KB sur S3 Vectors, phase 2 GraphRAG Neptune Analytics.
- Refacturation : tags `UseCase`, `BusinessUnit`, `CostCenter`, `Owner`, `Environment`,
  `DataClassification`, `Phase`, `ExpiryDate`, `ManagedBy` ; activer les cost allocation tags ;
  appels Bedrock via inference profiles tagués ; coûts partagés en `UseCase=shared` répartis par
  Cost Categories (split charge) ; un budget par use-case.
- Chiffrage estimé ($/mois) : socle ≈ 90–110 · uc01 ≈ 170–230 · uc02 phase 1 ≈ 90–110 · uc02 phase 2 ≈ 200–500.

## Prochaine étape
Lancer Claude Code **sur le PC** dans `C:\Users\TZ6429\gitlab\infrastructure-services\applications`
(`claude` ou `claude remote-control`), cloner la branche ci-dessus dans `docs-architecture`, puis :
> Lis `docs-architecture/docs/HANDOFF.md`. Analyse `trends-analysis` et `langgraph-agents`, puis adapte
> l'architecture, les schémas, le module Terraform `usecase-baseline` et le chiffrage à leurs conventions
> réelles (nommage, tags existants, structure Terraform, packaging Lambda, VPC, CI GitLab). Signale ce qui
> peut être mutualisé à partir de l'existant. Écris les résultats dans `docs-architecture\`.
