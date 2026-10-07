# replica/

The working files of the [Replica skill pack](https://github.com/Jakeschincariol/replica-skill)
(MIT), used to plan and check the one TIHE app: live classes in the style of Adobe Connect and
a protected library in the style of SpotPlayer. Clean-room: public sources only, and neither
product's name, assets or copy appear in the app.

| file | skill | what |
| --- | --- | --- |
| [recon.md](recon.md) | replica-recon | screens, flows, components, data model, sources, size |
| [features.csv](features.csv) | replica-recon, updated by replica-build | the feature matrix parity is scored from |
| [architecture.md](architecture.md) | replica-architect | what changes in the existing stack, and the build order |
| [design/](design/) | replica-design | the glass theme as tokens, checked for contrast |
| [build-log.md](build-log.md) | replica-build | what was built, what is partial |
| [test-plan.md](test-plan.md) | replica-test | cases per flow, and where each is automated |
| [parity.md](parity.md) | replica-diff | the parity score and what is missing |

replica-entrepreneur, replica-brand and replica-launch do not apply: TIHE is the institute's own
product with its own name, for its own students, not a clone for sale. replica-deploy's role is
taken by the Compose server and the installer workflow.

Re-run the checks, with the pack in `.claude/skills/`:

```bash
python3 .claude/skills/replica-design/contrast.py replica/design/tokens.light.json
python3 .claude/skills/replica-design/contrast.py replica/design/tokens.dark.json
python3 .claude/skills/replica-diff/parity.py replica/features.csv
```
