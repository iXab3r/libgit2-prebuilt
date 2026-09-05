#![allow(non_snake_case)]

use git2::{
    build::CheckoutBuilder, FetchOptions, FetchPrune, IndexAddOption, Repository, ResetType,
    Signature,
};
use std::error::Error;
use std::fs;
use std::path::Path;

fn Commit(Repo: &Repository, Message: &str) -> Result<git2::Oid, git2::Error> {
    let mut Index = Repo.index()?;
    Index.add_all(["*"], IndexAddOption::DEFAULT, None)?;
    Index.write()?;
    let TreeId = Index.write_tree()?;
    let Tree = Repo.find_tree(TreeId)?;
    let Parent = Repo.head().ok().and_then(|Head| Head.peel_to_commit().ok());
    let Parents: Vec<_> = Parent.iter().collect();
    let Author = Signature::now("Native bundle smoke test", "smoke@example.invalid")?;
    Repo.commit(Some("HEAD"), &Author, &Author, Message, &Tree, &Parents)
}

fn LocalRoundTrip(Root: &Path) -> Result<(), Box<dyn Error>> {
    let OriginPath = Root.join("origin");
    let Origin = Repository::init(&OriginPath)?;
    fs::write(OriginPath.join("profile.txt"), "first")?;
    fs::write(OriginPath.join("данные.txt"), "unicode")?;
    let First = Commit(&Origin, "Initial state")?;
    assert!(Origin.statuses(None)?.is_empty());

    let CheckoutPath = Root.join("checkout");
    let Checkout = Repository::clone(OriginPath.to_str().unwrap(), &CheckoutPath)?;
    assert_eq!(Checkout.head()?.target(), Some(First));
    assert_eq!(
        fs::read_to_string(CheckoutPath.join("данные.txt"))?,
        "unicode"
    );

    fs::write(CheckoutPath.join("profile.txt"), "local edits")?;
    assert!(!Checkout.statuses(None)?.is_empty());
    fs::write(OriginPath.join("profile.txt"), "second")?;
    fs::remove_file(OriginPath.join("данные.txt"))?;
    let Second = Commit(&Origin, "Updated state")?;
    let Branch = Origin.head()?.shorthand().unwrap().to_owned();
    let mut Options = FetchOptions::new();
    Options.prune(FetchPrune::On);
    Checkout.find_remote("origin")?.fetch(
        &["+refs/heads/*:refs/remotes/origin/*"],
        Some(&mut Options),
        None,
    )?;
    let Tip = Checkout
        .find_reference(&format!("refs/remotes/origin/{Branch}"))?
        .peel_to_commit()?;
    assert_eq!(Tip.id(), Second);
    Checkout.reset(
        Tip.as_object(),
        ResetType::Hard,
        Some(CheckoutBuilder::new().force()),
    )?;
    assert_eq!(
        fs::read_to_string(CheckoutPath.join("profile.txt"))?,
        "second"
    );
    assert!(!CheckoutPath.join("данные.txt").exists());
    assert!(Checkout.statuses(None)?.is_empty());
    assert_eq!(
        Checkout.head()?.peel_to_commit()?.summary(),
        Some("Updated state")
    );
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let Version = git2::Version::get();
    assert_eq!(Version.libgit2_version(), (1, 8, 6));
    assert!(Version.https(), "HTTPS transport missing");
    assert!(Version.ssh(), "SSH transport missing");
    let Root = tempfile::tempdir()?;
    LocalRoundTrip(Root.path())?;
    let mut Builder = git2::build::RepoBuilder::new();
    let mut Fetch = FetchOptions::new();
    Fetch.depth(1);
    Builder.fetch_options(Fetch);
    let Remote = Builder.clone(
        "https://github.com/octocat/Hello-World.git",
        &Root.path().join("https"),
    )?;
    assert!(!Remote.head()?.peel_to_commit()?.tree()?.is_empty());
    println!("PASS: libgit2 1.8.6; HTTPS + SSH capabilities; init/commit/status/clone/fetch/hard-reset; Unicode paths; tracked deletion; public HTTPS clone");
    Ok(())
}
