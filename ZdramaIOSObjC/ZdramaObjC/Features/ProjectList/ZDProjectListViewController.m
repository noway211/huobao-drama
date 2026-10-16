#import "ZDProjectListViewController.h"
#import "ZDAppContainer.h"
#import "ZDProjectDetailViewController.h"

@implementation ZDProjectListViewController {
    NSArray<ZDDramaProject *> *_projects;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"项目";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _projects = [ZDAppContainer.shared.repository getProjects];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _projects.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"project"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"project"];
    ZDDramaProject *project = _projects[indexPath.row];
    cell.textLabel.text = project.title;
    cell.detailTextLabel.text = project.status;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.navigationController pushViewController:[[ZDProjectDetailViewController alloc] initWithProjectId:_projects[indexPath.row].id] animated:YES];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    ZDDramaProject *project = _projects[indexPath.row];
    ZDEpisode *episode = [ZDAppContainer.shared.repository getEpisodeForProject:project.id];
    if (episode) [ZDAppContainer.shared.coordinator cancelProjectId:project.id episodeId:episode.id];
    [ZDAppContainer.shared.repository deleteProject:project.id];
    NSMutableArray *remaining = [_projects mutableCopy];
    [remaining removeObjectAtIndex:indexPath.row];
    _projects = remaining;
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
