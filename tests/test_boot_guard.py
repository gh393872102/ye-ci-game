#!/usr/bin/env python3
"""Verify source fidelity and Boot failure behavior in disposable copies only."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True, type=Path)
parser.add_argument('--report-prefix', default='p0')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
engine = args.godot.resolve()
results = []


def check(condition, label):
    results.append({'check': label, 'passed': bool(condition)})
    print(('PASS ' if condition else 'FAIL ') + label)


manifest = json.loads((root / 'docs/source-manifest.json').read_text())
for kind in ['characters', 'ghosts']:
    data = (root / f'data/units/{kind}.csv').read_bytes()
    check(hashlib.sha256(data).hexdigest() == manifest[kind + '.csv']['sha256'],
          f'{kind}: exact source CSV SHA-256')
for path in sorted((root / 'data').rglob('*.csv')):
    data = path.read_bytes()
    check(not data.startswith(b'\xef\xbb\xbf') and b'\r' not in data,
          f'UTF-8 without BOM / LF: {path.relative_to(root)}')
    data.decode('utf-8')

for fault in ['missing_column', 'duplicate_id', 'unknown_skill', 'invalid_tide', 'invalid_battle', 'unknown_battle_unit', 'night_route', 'night_ritual', 'night_wave', 'mode_ai_stats', 'mode_unit', 'mode_post', 'night_objective', 'growth_missing_item', 'growth_effect', 'growth_source', 'growth_night_item', 'growth_template_item', 'roster_missing_skill', 'roster_missing_handler', 'roster_departure', 'roster_numeric', 'roster_routes']:
    with tempfile.TemporaryDirectory(prefix='ye-ci-boot-') as temp:
        project = Path(temp)
        for folder in ['data', 'src', 'scenes', 'resources']:
            shutil.copytree(root / folder, project / folder)
        for name in ['project.godot', 'default_bus_layout.tres']:
            shutil.copy2(root / name, project / name)
        table = project / 'data/units/characters.csv'
        lines = table.read_text().splitlines()
        if fault == 'missing_column':
            lines[0] = lines[0].replace('姓名', 'broken_name')
            expected = 'missing column'
        elif fault == 'duplicate_id':
            lines.append(lines[1])
            expected = 'duplicate id'
        elif fault.startswith('roster_'):
            target = project / 'data/units/p8_humans.json'
            content = json.loads(target.read_text())
            if fault == 'roster_missing_skill':
                del content['skills'][content['profiles']['H15']['skill_id']]
                expected = 'Missing P8 skill_id for H15'
            elif fault == 'roster_missing_handler':
                content['profiles']['H15']['skill_method'] = 'missing_action'
                expected = 'Missing P8 skill method: H15'
            elif fault == 'roster_departure':
                content['profiles']['H15']['may_briefly_leave_base'] = True
                expected = 'P8 departure permission mismatch: H15'
            elif fault == 'roster_numeric':
                content['abilities']['H31']['hunt_speed'] = -2
                expected = 'Invalid P8 ability parameter: H31'
            else:
                target = project / 'data/levels/p8_routes.json'
                content = json.loads(target.read_text())
                content['window_side_passage']['unit_ids'].append('G24')
                expected = 'Invalid P8 route permission'
            target.write_text(json.dumps(content, ensure_ascii=False))
        elif fault.startswith('growth_'):
            if fault == 'growth_template_item':
                target = project / 'data/modes/p7_growth_templates.json'
                content = json.loads(target.read_text())
                content['ritual_break']['loadouts']['H01'][0] = 'I99'
                expected = 'Unknown or repeated growth observation item'
            elif fault == 'growth_night_item':
                target = project / 'data/nights/p7_growth_night.json'
                content = json.loads(target.read_text())
                content['starting_inventory']['shouxiang']['I99'] = 1
                expected = 'Unknown growth night starting item'
            elif fault == 'growth_source':
                target = project / 'data/items/growth_rules.json'
                content = json.loads(target.read_text())
                content['mutations']['V01']['sources'].append('G99')
                expected = 'Unknown mutation source'
            else:
                target = project / 'data/items/censers.json'
                content = json.loads(target.read_text())
                if fault == 'growth_missing_item':
                    del content['I10']
                    expected = 'Missing growth effect'
                else:
                    content['I10']['effect_id'] = 'unimplemented_effect'
                    expected = 'Invalid/unknown growth item'
            target.write_text(json.dumps(content, ensure_ascii=False))
        elif fault in ['mode_ai_stats', 'mode_unit', 'mode_post']:
            mode_path = project / 'data/modes/p6_modes.json'
            modes = json.loads(mode_path.read_text())
            if fault == 'mode_ai_stats':
                modes['ai_levels']['fierce']['attack_multiplier'] = 2
                expected = 'ferocity cannot alter unit stats'
            elif fault == 'mode_unit':
                modes['allowed_ghosts'].append('G32')
                expected = 'Unknown modes unit'
            else:
                modes['defaults']['humans'][0]['post'] = 'court_center'
                expected = 'Modes default deployment must be a cover post'
            mode_path.write_text(json.dumps(modes))
        elif fault in ['night_route', 'night_ritual', 'night_wave', 'night_objective']:
            night_path = project / 'data/nights/example_night.json'
            night = json.loads(night_path.read_text())
            if fault == 'night_route':
                night['nodes'][0]['next'] = ['missing_node']
                expected = 'Broken night node edge'
            elif fault == 'night_ritual':
                night['ritual'] = 'unimplemented_ritual'
                expected = 'P5 only implements example_incense'
            elif fault == 'night_objective':
                night['nodes'][0]['objectives']['duoming']['primary'] = 'unimplemented_capture'
                expected = 'Unknown/incomplete night seat objectives'
            else:
                profile_path = project / 'data/nights/p5_battle_profiles.json'
                profile = json.loads(profile_path.read_text())
                profile['entry']['waves'][0]['G99'] = 1
                profile_path.write_text(json.dumps(profile))
                expected = 'Unknown night wave unit'
            night_path.write_text(json.dumps(night))
        elif fault in ['invalid_battle', 'unknown_battle_unit']:
            battle_path = project / 'data/levels/p4_battle.json'
            battle = json.loads(battle_path.read_text())
            if fault == 'invalid_battle':
                battle['repair']['cost'] = -6
                expected = 'Invalid battle numeric range'
            else:
                battle['purchases']['H99'] = 5
                expected = 'Invalid battle unit reference'
            battle_path.write_text(json.dumps(battle))
        elif fault == 'invalid_tide':
            tide_path = project / 'data/levels/p3_tide.json'
            tide = json.loads(tide_path.read_text())
            tide['large_speed'] = 4.0
            tide_path.write_text(json.dumps(tide))
            expected = 'Invalid tide scale/speed/capacity'
        else:
            catalog_path = project / 'data/units/p2_combat.json'
            catalog = json.loads(catalog_path.read_text())
            catalog['profiles']['H09']['skill_id'] = 'missing_skill'
            catalog_path.write_text(json.dumps(catalog, ensure_ascii=False))
            expected = 'Unknown skill_id'
        table.write_text('\n'.join(lines) + '\n')
        run = subprocess.run([str(engine), '--headless', '--path', str(project), '--quit-after', '10'],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
        check(run.returncode == 1 and expected in run.stdout and 'SCRIPT ERROR' not in run.stdout,
              'Boot refuses battle with ' + fault)

output = {'checks': len(results), 'failures': sum(not r['passed'] for r in results), 'results': results}
(root / f'docs/phase-reports/{args.report_prefix}-source-boot-results.json').write_text(json.dumps(output, indent=2) + '\n')
raise SystemExit(1 if output['failures'] else 0)
